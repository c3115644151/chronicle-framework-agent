[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$evidenceRoot = [IO.Path]::GetFullPath($EvidencePath)
$harnessTemp = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_TEMP', 'Process')
if ([string]::IsNullOrWhiteSpace($harnessTemp) -or -not (Test-Path -LiteralPath $harnessTemp -PathType Container)) {
    throw 'Agent Host package verification requires the active Run-Harness evidence directory.'
}
$harnessTempRoot = [IO.Path]::GetFullPath($harnessTemp).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $evidenceRoot.StartsWith($harnessTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Agent Host package evidence must remain inside the current disposable Harness run.'
}

$proxyUri = 'http://127.0.0.1:7890'
$proxyReady = Test-NetConnection -ComputerName '127.0.0.1' -Port 7890 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $proxyReady) { throw 'The configured local package-download proxy on port 7890 is unavailable.' }

$packageId = 'ChronicleAgentHost-win-x64-' + [Guid]::NewGuid().ToString('N')
$packageRoot = Join-Path 'D:\ChronicleFramework\BuildCache\Packages' $packageId
$repositoryRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'Could not resolve the source repository before selecting package staging.' }
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$packageRootFull = [IO.Path]::GetFullPath($packageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($packageRootFull.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Self-contained package staging must be outside the source repository so binary runtime files cannot contaminate normal source builds.'
}
$publishRoot = Join-Path $packageRoot 'publish'
$buildOutputRoot = Join-Path $packageRoot 'build'
$consumerWorkingDirectory = Join-Path $evidenceRoot 'AgentHostPackageConsumerWorkingDirectory'
$nugetRoot = 'D:\ChronicleFramework\BuildCache\NuGetPackages'
New-Item -ItemType Directory -Path $publishRoot,$buildOutputRoot,$consumerWorkingDirectory,$nugetRoot -Force | Out-Null

$previousEnvironment = @{}
foreach ($name in @('NUGET_PACKAGES', 'HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$buildLog = ''
$buildExitCode = 1
try {
    [Environment]::SetEnvironmentVariable('NUGET_PACKAGES', $nugetRoot, 'Process')
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy')) {
        [Environment]::SetEnvironmentVariable($name, $proxyUri, 'Process')
    }
$baseOutputArgument = "-p:BaseOutputPath=$buildOutputRoot\"
$publishArguments = @('publish',$project,'--configuration','Release','--runtime','win-x64','--self-contained','true','-p:UseAppHost=true',$baseOutputArgument,'-o',$publishRoot)
$buildLog = & dotnet @publishArguments 2>&1 | Out-String
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0 -and $buildLog -match 'NU1900') {
    [xml]$hostProject = Get-Content -LiteralPath $project -Raw -Encoding UTF8
    if (@($hostProject.Project.ItemGroup.PackageReference).Count -gt 0) {
        throw "NuGet audit metadata was unreachable and this Host project contains package dependencies; refusing an unaudited fallback. $buildLog"
    }
    $auditFallbackArguments = @($publishArguments[0..($publishArguments.Count - 1)]) + '-p:NuGetAudit=false'
    $auditFallbackLog = & dotnet @auditFallbackArguments 2>&1 | Out-String
    $auditFallbackExitCode = $LASTEXITCODE
    $buildLog = "Initial NuGet vulnerability-feed request failed with NU1900; retrying package restore without that unavailable audit endpoint. Dependency restore remains enabled.`n$buildLog`nAudit-metadata fallback publish:`n$auditFallbackLog"
    $buildExitCode = $auditFallbackExitCode
}
}
finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

if ($buildExitCode -ne 0) { throw "Self-contained win-x64 publish failed (exit=$buildExitCode). Restore used proxy port 7890 and D: package cache. $buildLog" }

$hostExe = Join-Path $publishRoot 'ChronicleAgentHost.exe'
$requiredRuntimeFiles = @('hostfxr.dll', 'hostpolicy.dll', 'coreclr.dll', 'System.Private.CoreLib.dll')
$missingRuntimeFiles = @($requiredRuntimeFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $publishRoot $_) -PathType Leaf) })
if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf) -or $missingRuntimeFiles.Count -gt 0) {
    throw "The publish output is incomplete for a self-contained Windows runtime. Missing=$($missingRuntimeFiles -join ',')"
}
if (@(Get-ChildItem -LiteralPath $publishRoot -Recurse -File -Filter 'ChronicleAgentSettings.json').Count -gt 0) {
    throw 'The publish output unexpectedly contains a user MCM provider profile.'
}

function Invoke-PackagedHost([string]$ExecutablePath, [string]$Argument)
{
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExecutablePath
    $startInfo.Arguments = $Argument
    $startInfo.WorkingDirectory = $consumerWorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Could not start packaged Host command '$Argument'." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) {
        try { $process.Kill($true) } catch { }
        throw "Packaged Host command '$Argument' exceeded its 20 second bound."
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw "Packaged Host command '$Argument' failed (exit=$($process.ExitCode)); stderr=$stderr" }
    try { return $stdout | ConvertFrom-Json }
    catch { throw "Packaged Host command '$Argument' did not return JSON." }
}

function Invoke-PackagedHostUnboundParentProbe([string]$ExecutablePath)
{
    $probeRoot = Join-Path $evidenceRoot 'AgentHostUnboundParentProbe'
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
    $commandPath = Join-Path $probeRoot 'command.json'
    $responseRoot = Join-Path $probeRoot 'responses'
    $arguments = '--campaign-loop --protocol-root "' + $probeRoot + '"'
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExecutablePath
    $startInfo.Arguments = $arguments
    $startInfo.WorkingDirectory = $consumerWorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start packaged Host parent-identity probe.' }
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $request = [ordered]@{
            runId = 'parent-identity-negative-probe'
            parentProcessId = 2147483000
            parentProcessStartTimeUtcTicks = 1
            goal = 'This request must be rejected before any Native or model work.'
            maxDecisions = 1
            maxElapsedSeconds = 1
            allowedActionNames = @('mapSettlementTargets','move')
        }
        $process.StandardInput.WriteLine(($request | ConvertTo-Json -Compress))
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { throw 'Packaged Host did not reject an unbound Bannerlord parent within 10 seconds.' }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        try { $errorReceipt = $stderr | ConvertFrom-Json }
        catch { throw 'Packaged Host parent-identity rejection did not produce a readable error receipt.' }
        if ($process.ExitCode -ne 2 -or $errorReceipt.error -ne 'campaign-parent-not-running' -or
            (Test-Path -LiteralPath $commandPath) -or @(Get-ChildItem -LiteralPath $responseRoot -File -ErrorAction SilentlyContinue).Count -gt 0 -or
            -not [string]::IsNullOrWhiteSpace($stdout)) {
            throw 'An unbound parent must be rejected before Host writes a Native command, response, or normal output.'
        }
        return [ordered]@{ Passed = $true; ErrorCode = [string]$errorReceipt.error; NativeCommandWritten = $false; ResponseFilesWritten = $false }
    }
    finally {
        if (-not $process.HasExited) { try { $process.Kill($true); $process.WaitForExit(1000) } catch { } }
        $process.Dispose()
    }
}

$packageHealth = Invoke-PackagedHost -ExecutablePath $hostExe -Argument '--package-health'
$version = Invoke-PackagedHost -ExecutablePath $hostExe -Argument '--version'
$providerSelfTest = Invoke-PackagedHost -ExecutablePath $hostExe -Argument '--provider-self-test'
$unboundParentProbe = Invoke-PackagedHostUnboundParentProbe -ExecutablePath $hostExe
foreach ($receipt in @($packageHealth, $version)) {
    if ($receipt.status -ne 'ready' -or $receipt.product -ne 'ChronicleAgentHost' -or
        $receipt.processArchitecture -ne 'X64' -or -not [bool]$receipt.is64BitProcess -or
        [int]$receipt.protocolVersion -ne 1 -or [string]$receipt.version -notmatch '^0\.1\.0') {
        throw 'Packaged Host version/health receipt did not match the expected Windows x64 product contract.'
    }
}
if ($providerSelfTest.status -ne 'ready' -and $providerSelfTest.passed -ne $true) {
    throw 'The packaged Host did not pass its provider/decision-loop contract self-test.'
}
if ([int]$providerSelfTest.modelCalls -ne 0 -or [int]$providerSelfTest.nativeCommands -ne 0 -or
    @($providerSelfTest.scenarios | Where-Object { -not $_.passed }).Count -gt 0) {
    throw 'The packaged Host provider/decision-loop regression must complete without a live model or Native game command.'
}
if (-not [bool]$unboundParentProbe.Passed) { throw 'Packaged Host did not enforce its Bannerlord parent process identity before starting a campaign loop.' }

$files = @(Get-ChildItem -LiteralPath $publishRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path = $_.FullName.Substring($publishRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar).Replace('\', '/')
        sizeBytes = [long]$_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$totalBytes = [long]0
foreach ($file in $files) { $totalBytes += [long]$file.sizeBytes }
$manifestPath = Join-Path $evidenceRoot 'AgentHostPackageManifest.json'
$manifest = [ordered]@{
    product = 'ChronicleAgentHost'
    version = [string]$packageHealth.version
    runtimeIdentifier = 'win-x64'
    selfContained = $true
    fileCount = $files.Count
    totalBytes = $totalBytes
    executable = 'ChronicleAgentHost.exe'
    files = $files
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$result = [ordered]@{
    Passed = $true
    RuntimeIdentifier = 'win-x64'
    SelfContained = $true
    PackageVersion = [string]$packageHealth.version
    PackageFileCount = $files.Count
    PackageBytes = $totalBytes
    PackageHealth = $packageHealth
    VersionReceipt = $version
    ProviderContractSelfTestPassed = [bool]$providerSelfTest.passed
    ProviderContractSelfTestScenarioCount = @($providerSelfTest.scenarios).Count
    CampaignLoopSelfTestScenarioCount = @($providerSelfTest.scenarios | Where-Object { $_.scenario -like 'campaign-loop-*' }).Count
    SharedDecisionCycleScenarioCount = @($providerSelfTest.scenarios | Where-Object { $_.scenario -like 'shared-agent-host-decision-cycle-*' }).Count
    SelfTestModelCalls = [int]$providerSelfTest.modelCalls
    SelfTestNativeCommands = [int]$providerSelfTest.nativeCommands
    UnboundParentRejected = [bool]$unboundParentProbe.Passed
    UnboundParentErrorCode = [string]$unboundParentProbe.ErrorCode
    UnboundParentNativeCommandWritten = [bool]$unboundParentProbe.NativeCommandWritten
    RestoreProxy = '127.0.0.1:7890'
    NuGetCacheRoot = $nugetRoot
    ConsumerWorkingDirectorySeparatedFromPackage = ($consumerWorkingDirectory -ne $publishRoot)
    UserConfigurationIncluded = $false
    ManifestPath = $manifestPath
    PublishRoot = $publishRoot
    PackageRoot = $packageRoot
    ProcessExited = $true
}
$result | ConvertTo-Json -Depth 6
