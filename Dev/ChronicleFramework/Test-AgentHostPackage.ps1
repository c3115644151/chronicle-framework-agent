[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$EvidencePath,
    [string]$CleanupPackageRoot,
    [switch]$RetainRuntimePackage
)

$ErrorActionPreference = 'Stop'

function Invoke-StaleAgentHostPackageCleanup {
    $packageParent = [IO.Path]::GetFullPath('D:\ChronicleFramework\BuildCache\Packages').TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $packageParent -PathType Container)) {
        return [ordered]@{ Examined = 0; Removed = 0; DeletedBytes = [long]0; Skipped = $false; Reason = 'cache-directory-absent' }
    }
    if (@(Get-Process -Name 'Bannerlord*','ChronicleAgentHost' -ErrorAction SilentlyContinue).Count -gt 0) {
        return [ordered]@{ Examined = 0; Removed = 0; DeletedBytes = [long]0; Skipped = $true; Reason = 'game-or-host-process-active' }
    }

    $cutoffUtc = [DateTime]::UtcNow.AddHours(-24)
    $candidates = @(Get-ChildItem -LiteralPath $packageParent -Directory -Filter 'ChronicleAgentHost-win-x64-*' -ErrorAction Stop |
        Where-Object { $_.Name -match '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$' -and $_.CreationTimeUtc -lt $cutoffUtc })
    $deletedBytes = [long]0
    $removed = 0
    foreach ($candidate in $candidates) {
        $resolvedRoot = [IO.Path]::GetFullPath($candidate.FullName).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if ([IO.Path]::GetFullPath((Split-Path -Parent $resolvedRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) -ne $packageParent -or
            (Split-Path -Leaf $resolvedRoot) -notmatch '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$') {
            throw 'Stale package cleanup candidate escaped the exact unique D: Agent Host package directory.'
        }
        $fileBytes = (Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum
        if (-not $fileBytes) { $fileBytes = 0 }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $resolvedRoot) { throw 'A stale Agent Host package staging directory remains after cleanup.' }
        $deletedBytes += [long]$fileBytes
        $removed++
    }
    return [ordered]@{ Examined = $candidates.Count; Removed = $removed; DeletedBytes = $deletedBytes; Skipped = $false; OlderThanHours = 24; Reason = 'verified-unique-temporary-package-staging' }
}

if (-not [string]::IsNullOrWhiteSpace($CleanupPackageRoot)) {
    $packageParent = [IO.Path]::GetFullPath('D:\ChronicleFramework\BuildCache\Packages').TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $resolvedPackageRoot = [IO.Path]::GetFullPath($CleanupPackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::GetFullPath((Split-Path -Parent $resolvedPackageRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) -ne $packageParent -or
        (Split-Path -Leaf $resolvedPackageRoot) -notmatch '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$') {
        throw 'Cleanup-only mode accepts only one exact unique D: Agent Host package directory.'
    }
    if (@(Get-Process -Name 'Bannerlord*','ChronicleAgentHost' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Cleanup-only mode refuses while a Bannerlord or Agent Host process may still use the package.'
    }
    if (Test-Path -LiteralPath $resolvedPackageRoot -PathType Container) {
        $cleanupFailure = $null
        for ($cleanupAttempt = 1; $cleanupAttempt -le 5; $cleanupAttempt++) {
            try {
                Remove-Item -LiteralPath $resolvedPackageRoot -Recurse -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $resolvedPackageRoot)) { $cleanupFailure = $null; break }
                $cleanupFailure = 'Package directory still exists after removal.'
            }
            catch { $cleanupFailure = $_.Exception.Message }
            if ($cleanupAttempt -lt 5) { Start-Sleep -Milliseconds (250 * $cleanupAttempt) }
        }
        if ($cleanupFailure) { throw "Cleanup-only mode failed: $cleanupFailure" }
    }
    [pscustomobject]@{ CleanupOnly = $true; PackageRoot = $resolvedPackageRoot; Removed = -not (Test-Path -LiteralPath $resolvedPackageRoot) } | ConvertTo-Json -Compress
    exit 0
}
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or [string]::IsNullOrWhiteSpace($EvidencePath)) { throw 'Package verification requires ProjectPath and EvidencePath, or one exact CleanupPackageRoot.' }
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
$projectDirectory = Split-Path -Parent $project
[xml]$hostProject = Get-Content -LiteralPath $project -Raw -Encoding UTF8
$packageReferences = @($hostProject.SelectNodes('//PackageReference'))
$unsupportedPackageReferences = @($packageReferences | Where-Object { $_.Include -ne 'Microsoft.ML.Tokenizers' -or $_.Version -ne '[2.0.1]' })
$packageLockPath = Join-Path $projectDirectory 'packages.lock.json'
if ($packageReferences.Count -ne 1 -or $unsupportedPackageReferences.Count -gt 0 -or
    $hostProject.Project.PropertyGroup.RestorePackagesWithLockFile -ne 'true' -or
    -not (Test-Path -LiteralPath $packageLockPath -PathType Leaf)) {
    throw 'Agent Host requires one reviewed, exactly pinned tokenizer package and a committed dependency lock file.'
}
$packageLock = Get-Content -LiteralPath $packageLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$packageLock.dependencies.'net8.0'.'Microsoft.ML.Tokenizers'.resolved -ne '2.0.1' -or
    [string]$packageLock.dependencies.'net8.0'.'Google.Protobuf'.resolved -ne '3.30.2' -or
    $null -eq $packageLock.dependencies.'net8.0/win-x64') {
    throw 'Agent Host package lock does not match the reviewed Microsoft tokenizer and Protocol Buffers dependency versions.'
}
$stalePackageCleanup = Invoke-StaleAgentHostPackageCleanup

function Test-BoundedTcpPort
{
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][ValidateRange(1,65535)][int]$Port,
        [ValidateRange(1,5000)][int]$TimeoutMilliseconds = 500
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    $asyncResult = $null
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { return $false }
        $client.EndConnect($asyncResult)
        return $client.Connected
    }
    catch { return $false }
    finally {
        if ($asyncResult) { $asyncResult.AsyncWaitHandle.Close() }
        $client.Dispose()
    }
}

$proxyProbeListener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
try {
    $proxyProbeListener.Start()
    $proxyProbePort = ([Net.IPEndPoint]$proxyProbeListener.LocalEndpoint).Port
    if (-not (Test-BoundedTcpPort -HostName '127.0.0.1' -Port $proxyProbePort)) { throw 'Bounded TCP proxy probe failed against a live loopback listener.' }
}
finally { $proxyProbeListener.Stop() }
if (Test-BoundedTcpPort -HostName '127.0.0.1' -Port $proxyProbePort) { throw 'Bounded TCP proxy probe accepted a closed loopback port.' }

$proxyUri = 'http://127.0.0.1:7890'
$proxyReady = Test-BoundedTcpPort '127.0.0.1' 7890
if (-not $proxyReady) { throw 'The configured local package-download proxy on port 7890 is unavailable.' }

$packageId = 'ChronicleAgentHost-win-x64-' + [Guid]::NewGuid().ToString('N')
$packageParent = [IO.Path]::GetFullPath('D:\ChronicleFramework\BuildCache\Packages').TrimEnd([IO.Path]::DirectorySeparatorChar)
$packageRoot = Join-Path $packageParent $packageId
$repositoryRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'Could not resolve the source repository before selecting package staging.' }
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$packageRootFull = [IO.Path]::GetFullPath($packageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($packageRootFull.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Self-contained package staging must be outside the source repository so binary runtime files cannot contaminate normal source builds.'
}
if ([IO.Path]::GetFullPath((Split-Path -Parent $packageRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar) -ne $packageParent -or
    (Split-Path -Leaf $packageRoot) -notmatch '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$' -or
    (Test-Path -LiteralPath $packageRoot)) {
    throw 'Refusing package staging outside the exact unique Chronicle Agent Host cache directory.'
}
$publishRoot = Join-Path $packageRoot 'publish'
$buildOutputRoot = Join-Path $packageRoot 'build'
$consumerWorkingDirectory = Join-Path $evidenceRoot 'AgentHostPackageConsumerWorkingDirectory'
$nugetRoot = 'D:\ChronicleFramework\BuildCache\NuGetPackages'
$packageRootCreated = $false
$result = $null
try {
New-Item -ItemType Directory -Path $publishRoot,$buildOutputRoot,$consumerWorkingDirectory,$nugetRoot -Force | Out-Null
$packageRootCreated = $true

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
$publishArguments = @('publish',$project,'--configuration','Release','--runtime','win-x64','--self-contained','true','-p:UseAppHost=true','-p:RestoreLockedMode=true',$baseOutputArgument,'-o',$publishRoot)
$buildLog = & dotnet @publishArguments 2>&1 | Out-String
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0 -and $buildLog -match 'NU1900') {
    if ($packageReferences.Count -ne 1 -or $unsupportedPackageReferences.Count -gt 0 -or
        -not (Test-Path -LiteralPath $packageLockPath -PathType Leaf)) {
        throw "NuGet audit metadata was unreachable and the Host project contains an unreviewed/unlocked dependency; refusing an unaudited fallback. $buildLog"
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
foreach ($noticeFile in @('THIRD-PARTY-NOTICES.txt','DeepSeekV4Tokenizer-LICENSE.txt','Microsoft.ML.Tokenizers-LICENSE.txt','Microsoft.ML.Tokenizers-THIRD-PARTY-NOTICES.txt','Google.Protobuf-LICENSE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $publishRoot (Join-Path 'Resources' $noticeFile)) -PathType Leaf)) {
        throw "The Agent Host distribution is missing third-party notice '$noticeFile'."
    }
}
if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf) -or $missingRuntimeFiles.Count -gt 0) {
    throw "The publish output is incomplete for a self-contained Windows runtime. Missing=$($missingRuntimeFiles -join ',')"
}
if (@(Get-ChildItem -LiteralPath $publishRoot -Recurse -File -Filter 'ChronicleAgentSettings.json').Count -gt 0) {
    throw 'The publish output unexpectedly contains a user MCM provider profile.'
}

function Invoke-PackagedHost([string]$ExecutablePath, [string]$Argument, [int]$TimeoutMilliseconds = 20000)
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
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        try { $process.Kill($true) } catch { }
        throw "Packaged Host command '$Argument' exceeded its $([int]($TimeoutMilliseconds / 1000)) second bound."
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
$providerSelfTest = Invoke-PackagedHost -ExecutablePath $hostExe -Argument '--provider-self-test' -TimeoutMilliseconds 180000
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
$companionProjection = @($providerSelfTest.scenarios | Where-Object { $_.scenario -eq 'establish-clan-companion-model-observation-compacts-raw-mission-agent-roster-and-preserves-current-wanderer-candidates' })
if ($companionProjection.Count -ne 1 -or -not [bool]$companionProjection[0].passed -or
    [int]$companionProjection[0].missionBytesSaved -le 0 -or
    [int]$companionProjection[0].estimatedPromptTokensSaved -le 0) {
    throw 'The packaged Host must retain a machine-readable Companion observation-projection receipt with both byte and tokenizer-estimate savings.'
}
$companionProjectionSummary = [ordered]@{
    scenario = [string]$companionProjection[0].scenario
    originalMissionBytes = [int]$companionProjection[0].originalMissionBytes
    projectedMissionBytes = [int]$companionProjection[0].projectedMissionBytes
    missionBytesSaved = [int]$companionProjection[0].missionBytesSaved
    fullPromptTokens = [int]$companionProjection[0].fullPromptTokens
    projectedPromptTokens = [int]$companionProjection[0].projectedPromptTokens
    estimatedPromptTokensSaved = [int]$companionProjection[0].estimatedPromptTokensSaved
    passed = [bool]$companionProjection[0].passed
}
$recruitmentPrefixScenario = @($providerSelfTest.scenarios | Where-Object { $_.scenario -eq 'establish-clan-recruitment-orders-stable-context-before-changing-map-state-for-prefix-cache' })
if ($recruitmentPrefixScenario.Count -ne 1 -or -not [bool]$recruitmentPrefixScenario[0].passed -or
    [int]$recruitmentPrefixScenario[0].cacheablePrefixTokenGain -le 0) {
    throw 'The packaged Host must retain tokenizer evidence that placing stable PartySize context before changing map state increases the exact reusable prompt prefix.'
}
$recruitmentPromptCachePrefixSummary = [ordered]@{
    scenario = [string]$recruitmentPrefixScenario[0].scenario
    legacyCommonPrefixTokens = [int]$recruitmentPrefixScenario[0].legacyCommonPrefixTokens
    cacheOrderedCommonPrefixTokens = [int]$recruitmentPrefixScenario[0].cacheOrderedCommonPrefixTokens
    cacheablePrefixTokenGain = [int]$recruitmentPrefixScenario[0].cacheablePrefixTokenGain
    passed = [bool]$recruitmentPrefixScenario[0].passed
}
$goldSalePrefixScenario = @($providerSelfTest.scenarios | Where-Object { $_.scenario -eq 'gold-sale-orders-stable-goal-and-receipt-context-before-changing-map-state-for-prefix-cache' })
if ($goldSalePrefixScenario.Count -lt 1 -or
    @($goldSalePrefixScenario | Where-Object { -not [bool]$_.passed -or [int]$_.cacheablePrefixTokenGain -le 0 }).Count -gt 0) {
    throw 'The packaged Host must retain tokenizer evidence that placing stable Gold objective context before changing map state increases the exact reusable prompt prefix.'
}
$goldSalePromptCachePrefixSummary = [ordered]@{
    scenario = [string]$goldSalePrefixScenario[0].scenario
    legacyCommonPrefixTokens = [int]$goldSalePrefixScenario[0].legacyCommonPrefixTokens
    cacheOrderedCommonPrefixTokens = [int]$goldSalePrefixScenario[0].cacheOrderedCommonPrefixTokens
    cacheablePrefixTokenGain = [int]$goldSalePrefixScenario[0].cacheablePrefixTokenGain
    passed = [bool]$goldSalePrefixScenario[0].passed
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
    companionObservationProjection = $companionProjectionSummary
    recruitmentPromptCachePrefix = $recruitmentPromptCachePrefixSummary
    goldSalePromptCachePrefix = $goldSalePromptCachePrefixSummary
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
    BattleSimulationLoopSelfTestScenarioCount = @($providerSelfTest.scenarios | Where-Object { $_.scenario -like 'battle-loop-*' }).Count
    SharedDecisionCycleScenarioCount = @($providerSelfTest.scenarios | Where-Object { $_.scenario -like 'shared-agent-host-decision-cycle-*' }).Count
    CompanionObservationProjection = $companionProjectionSummary
    RecruitmentPromptCachePrefix = $recruitmentPromptCachePrefixSummary
    GoldSalePromptCachePrefix = $goldSalePromptCachePrefixSummary
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
    PackageArtifactsRetained = [bool]$RetainRuntimePackage
    PublishRoot = if ($RetainRuntimePackage) { $publishRoot } else { $null }
    PackageRoot = if ($RetainRuntimePackage) { $packageRoot } else { $null }
    RuntimeExecutablePath = if ($RetainRuntimePackage) { Join-Path $publishRoot 'ChronicleAgentHost.exe' } else { $null }
    StalePackageCleanup = $stalePackageCleanup
    ProcessExited = $true
}

if ($RetainRuntimePackage) {
    $runtimeReceipt = [ordered]@{
        PackageRoot = $packageRoot
        PublishRoot = $publishRoot
        RuntimeExecutablePath = Join-Path $publishRoot 'ChronicleAgentHost.exe'
        PackageVersion = [string]$packageHealth.version
        RuntimeIdentifier = 'win-x64'
        SelfContained = $true
        SourceControlCommit = (git -C $repositoryRoot rev-parse HEAD 2>$null | Out-String).Trim()
    }
    $runtimeReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'AgentHostRuntimePackage.json') -Encoding UTF8
}
}
finally {
    if ($packageRootCreated -and -not ($RetainRuntimePackage -and $result -and [bool]$result.Passed) -and (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        $resolvedPackageRoot = [IO.Path]::GetFullPath($packageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $resolvedPackageParent = [IO.Path]::GetFullPath((Split-Path -Parent $resolvedPackageRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($resolvedPackageParent -ne $packageParent -or (Split-Path -Leaf $resolvedPackageRoot) -notmatch '^ChronicleAgentHost-win-x64-[0-9a-f]{32}$') {
            throw 'Refusing to remove package staging outside the exact unique Chronicle Agent Host cache directory.'
        }
        $cleanupFailure = $null
        for ($cleanupAttempt = 1; $cleanupAttempt -le 5; $cleanupAttempt++) {
            try {
                Remove-Item -LiteralPath $resolvedPackageRoot -Recurse -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $resolvedPackageRoot)) { $cleanupFailure = $null; break }
                $cleanupFailure = 'Temporary self-contained package staging still exists after cleanup.'
            }
            catch { $cleanupFailure = $_.Exception.Message }
            if ($cleanupAttempt -lt 5) { Start-Sleep -Milliseconds (250 * $cleanupAttempt) }
        }
        if ($cleanupFailure -or (Test-Path -LiteralPath $resolvedPackageRoot)) { throw "Temporary self-contained package staging cleanup failed after bounded retry: $cleanupFailure" }
    }
}
$result | ConvertTo-Json -Depth 6
