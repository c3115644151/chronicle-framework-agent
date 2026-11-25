#Requires -Version 7.0
[CmdletBinding()]
param([string]$CleanupGeneratedRoot)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'

function Remove-IsolatedTree([string]$Path, [string]$AllowedParent, [string]$ExpectedLeafPattern) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rootFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $parentFull = [IO.Path]::GetFullPath($AllowedParent).TrimEnd('\') + '\'
    if (-not $rootFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($rootFull) -notmatch $ExpectedLeafPattern) {
        throw "Refusing cleanup outside the exact generated test root: $rootFull"
    }
    if ((Get-Item -LiteralPath $rootFull -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to recursively clean a generated-root junction.' }
    $stack = [Collections.Stack]::new()
    $stack.Push([pscustomobject]@{ Path=$rootFull; PostOrder=$false })
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        if (-not $item.PostOrder) {
            $stack.Push([pscustomobject]@{ Path=$item.Path; PostOrder=$true })
            foreach ($entry in Get-ChildItem -LiteralPath $item.Path -Force) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
                    else { [IO.File]::Delete($entry.FullName) }
                }
                elseif ($entry.PSIsContainer) {
                    $stack.Push([pscustomobject]@{ Path=$entry.FullName; PostOrder=$false })
                }
                else {
                    [IO.File]::Delete($entry.FullName)
                }
            }
        }
        else { [IO.Directory]::Delete($item.Path, $false) }
    }
}

function Get-DirectorySnapshotSha256([string]$DirectoryPath) {
    $root = [IO.Path]::GetFullPath($DirectoryPath).TrimEnd('\') + '\'
    $rows = @(Get-ChildItem -LiteralPath $DirectoryPath -File -Recurse -Force | Sort-Object { $_.FullName.Substring($root.Length).Replace([IO.Path]::DirectorySeparatorChar,'/') } | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length).Replace([IO.Path]::DirectorySeparatorChar,'/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative|$($_.Length)|$hash"
    })
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $rows))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-CurrentSaveHashes {
    $hashes = @{}
    if (Test-Path -LiteralPath $sourceCampaignDirectory -PathType Container) {
        Get-ChildItem -LiteralPath $sourceCampaignDirectory -File -Filter '*.sav' | ForEach-Object { $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
    return $hashes
}

function Test-FormalSaveSetUnchanged([hashtable]$Baseline) {
    $current = Get-CurrentSaveHashes
    return ($Baseline.Count -eq $current.Count -and @($Baseline.Keys | Where-Object { -not $current.ContainsKey($_) -or $current[$_] -cne $Baseline[$_] }).Count -eq 0)
}

function Test-McmConfigUnchanged {
    if ($mcmHashBefore) { return (Test-Path -LiteralPath $mcmSettings -PathType Leaf) -and (Get-FileHash -LiteralPath $mcmSettings -Algorithm SHA256).Hash -ceq $mcmHashBefore }
    return -not (Test-Path -LiteralPath $mcmSettings -PathType Leaf)
}

function Assert-GameClosedForModuleFileChange([string]$Operation) {
    $running = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) { throw "Cannot $Operation while a Bannerlord game process is running; package module files stay untouched." }
}

if (-not [string]::IsNullOrWhiteSpace($CleanupGeneratedRoot)) {
    $cleanupParent = 'D:\ChronicleFramework\BuildCache\ReleasePackageTests'
    Remove-IsolatedTree -Path $CleanupGeneratedRoot -AllowedParent $cleanupParent -ExpectedLeafPattern '^test-[0-9a-f]{32}$'
    [pscustomobject]@{ Removed = -not (Test-Path -LiteralPath $CleanupGeneratedRoot) } | ConvertTo-Json -Compress
    exit 0
}

$stageRoot = $PSScriptRoot
$harnessRoot = Split-Path -Parent $stageRoot
$harnessTemp = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_TEMP', 'Process')
if ([string]::IsNullOrWhiteSpace($harnessTemp) -or -not (Test-Path -LiteralPath $harnessTemp -PathType Container)) {
    throw 'Release package verification requires the active Run-Harness evidence directory.'
}
$repositoryRoot = (& git -C $harnessRoot rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'Could not resolve the source repository.' }
$localSettings = Get-Content -LiteralPath (Join-Path $harnessRoot 'harness.local.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$gameRoot = [IO.Path]::GetFullPath([string]$localSettings.gameRoot)
$buildCacheRoot = 'D:\ChronicleFramework\BuildCache\ReleasePackageTests'
$runRoot = Join-Path $buildCacheRoot ('test-' + [Guid]::NewGuid().ToString('N'))
$firstOutput = Join-Path $runRoot 'build-a'
$secondOutput = Join-Path $runRoot 'build-b'
$overlayRoot = Join-Path $runRoot 'IsolatedGameRoot'
$extractRoot = Join-Path $runRoot 'ExtractedPackage'
$smokeResult = $null
$engineConfig = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
$mcmSettings = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModSettings\Global\ChronicleFramework\ChronicleAgentSettings.json'
$sourceCampaignDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$engineConfigOriginallyExists = Test-Path -LiteralPath $engineConfig -PathType Leaf
$engineConfigBytes = if (Test-Path -LiteralPath $engineConfig -PathType Leaf) { [IO.File]::ReadAllBytes($engineConfig) } else { $null }
$engineConfigHashBefore = if ($engineConfigBytes) { (Get-FileHash -LiteralPath $engineConfig -Algorithm SHA256).Hash } else { $null }
$mcmHashBefore = if (Test-Path -LiteralPath $mcmSettings -PathType Leaf) { (Get-FileHash -LiteralPath $mcmSettings -Algorithm SHA256).Hash } else { $null }
$saveHashesBefore = @{}
if (Test-Path -LiteralPath $sourceCampaignDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $sourceCampaignDirectory -File -Filter '*.sav' | ForEach-Object { $saveHashesBefore[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}

function Add-IsolatedJunction([string]$LinkPath, [string]$TargetPath) {
    if (Test-Path -LiteralPath $LinkPath) { throw "Isolated game overlay path already exists: $LinkPath" }
    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
}

function Add-IsolatedHardLink([string]$LinkPath, [string]$TargetPath) {
    if (Test-Path -LiteralPath $LinkPath) { throw "Isolated game overlay file already exists: $LinkPath" }
    New-Item -ItemType HardLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
}

function New-IsolatedGameRoot([string]$SourceRoot, [string]$DestinationRoot, [string]$PackagedModuleRoot) {
    $sourceFull = [IO.Path]::GetFullPath($SourceRoot)
    $destinationFull = [IO.Path]::GetFullPath($DestinationRoot)
    if ($destinationFull.StartsWith($sourceFull.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'The isolated game root cannot be created inside the installed game.' }
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null

    foreach ($entry in Get-ChildItem -LiteralPath $sourceFull -Force) {
        $destination = Join-Path $destinationFull $entry.Name
        if ($entry.PSIsContainer) {
            if ($entry.Name -in @('bin','Modules')) { New-Item -ItemType Directory -Path $destination | Out-Null }
            else { Add-IsolatedJunction $destination $entry.FullName }
        }
        else { Add-IsolatedHardLink $destination $entry.FullName }
    }

    $sourceBin = Join-Path $sourceFull 'bin'
    $destinationBin = Join-Path $destinationFull 'bin'
    foreach ($entry in Get-ChildItem -LiteralPath $sourceBin -Force) {
        $destination = Join-Path $destinationBin $entry.Name
        if ($entry.PSIsContainer -and $entry.Name -eq 'Win64_Shipping_Client') { New-Item -ItemType Directory -Path $destination | Out-Null }
        elseif ($entry.PSIsContainer) { Add-IsolatedJunction $destination $entry.FullName }
        else { Add-IsolatedHardLink $destination $entry.FullName }
    }
    $sourceClientBin = Join-Path $sourceBin 'Win64_Shipping_Client'
    $destinationClientBin = Join-Path $destinationBin 'Win64_Shipping_Client'
    foreach ($entry in Get-ChildItem -LiteralPath $sourceClientBin -Force) {
        $destination = Join-Path $destinationClientBin $entry.Name
        if ($entry.PSIsContainer) { Add-IsolatedJunction $destination $entry.FullName }
        else { Add-IsolatedHardLink $destination $entry.FullName }
    }

    $sourceModules = Join-Path $sourceFull 'Modules'
    $destinationModules = Join-Path $destinationFull 'Modules'
    foreach ($entry in Get-ChildItem -LiteralPath $sourceModules -Directory -Force) {
        $moduleManifestPath = Join-Path $entry.FullName 'SubModule.xml'
        if (-not (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf)) { continue }
        [xml]$moduleManifest = Get-Content -LiteralPath $moduleManifestPath -Encoding UTF8
        $moduleId = [string]$moduleManifest.Module.Id.value
        if ($moduleId -eq 'ChronicleFramework') { continue }
        Add-IsolatedJunction (Join-Path $destinationModules $entry.Name) $entry.FullName
    }
    $packagedDestination = Join-Path $destinationModules 'ChronicleFramework'
    if (Test-Path -LiteralPath $packagedDestination) { throw 'The isolated game root unexpectedly contains a preexisting Chronicle module.' }
    Copy-Item -LiteralPath $PackagedModuleRoot -Destination $packagedDestination -Recurse
    return $destinationFull
}

function Invoke-PackagedSmoke([string]$IsolatedRoot) {
    $smokeScript = Join-Path $stageRoot 'Test-Module.ps1'
    $stdoutPath = Join-Path $harnessTemp 'ReleasePackageSmoke.stdout.log'
    $stderrPath = Join-Path $harnessTemp 'ReleasePackageSmoke.stderr.log'
    $previousGameRoot = [Environment]::GetEnvironmentVariable('CHRONICLE_GAME_ROOT','Process')
    $previousSteamRoot = [Environment]::GetEnvironmentVariable('CHRONICLE_STEAM_ROOT','Process')
    $previousHarnessMode = [Environment]::GetEnvironmentVariable('CHRONICLE_HARNESS_MODE','Process')
    $process = $null
    [Environment]::SetEnvironmentVariable('CHRONICLE_GAME_ROOT',$IsolatedRoot,'Process')
    $realSteamRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
    [Environment]::SetEnvironmentVariable('CHRONICLE_STEAM_ROOT',$realSteamRoot,'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_MODE','smoke','Process')
    try {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $HarnessPowerShell
        $startInfo.Arguments = '-NoProfile -File "' + $smokeScript + '" -SkipBuild -TimeoutSeconds 45 -StabilitySeconds 8'
        $startInfo.WorkingDirectory = $harnessRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'Could not start the isolated module Smoke worker.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(90000)) {
            try { $process.Kill($true) } catch { }
            try { $process.WaitForExit() } catch { }
            [IO.File]::WriteAllText($stdoutPath, $stdoutTask.GetAwaiter().GetResult())
            [IO.File]::WriteAllText($stderrPath, $stderrTask.GetAwaiter().GetResult())
            throw 'Isolated release-package Smoke exceeded its 90-second bound; only the owned worker process tree was terminated.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($stdoutPath, $stdout)
        [IO.File]::WriteAllText($stderrPath, $stderr)
        if ($process.ExitCode -ne 0) { throw "Isolated release-package Smoke failed (exit=$($process.ExitCode)). $stderr $stdout" }
        $resultPath = Join-Path $harnessTemp 'SmokeResult.json'
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw 'Isolated Smoke did not write its structured SmokeResult.json.' }
        return Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    finally {
        if ($process -and -not $process.HasExited) {
            try { $process.Kill($true); $process.WaitForExit(5000) } catch { }
        }
        if ($process) { $process.Dispose() }
        [Environment]::SetEnvironmentVariable('CHRONICLE_GAME_ROOT',$previousGameRoot,'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_STEAM_ROOT',$previousSteamRoot,'Process')
        [Environment]::SetEnvironmentVariable('CHRONICLE_HARNESS_MODE',$previousHarnessMode,'Process')
    }
}

if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Close the running Bannerlord client before isolated release-package Smoke.' }
$runDirectoryCreated = $false
$packageReceipts = @()
$smokeSummary = $null
$installedModulePath = Join-Path $gameRoot 'Modules\ChronicleFramework'
$installedModuleTreeHashBefore = Get-DirectorySnapshotSha256 $installedModulePath
$evidence = [ordered]@{
    Passed = $false
    PackageReproducible = $false
    PackageSha256 = $null
    ManifestValidated = $false
    IsolatedSmokePassed = $false
    UninstallRemovedOnlyChronicleModule = $false
    RequiredModulesRemainAfterUninstall = $false
    UpdateRollbackCycleVerified = $false
    UpdateFixtureMode = 'manifest-only synthetic 0.1.0-to-0.1.1 fixture; binary/config schema intentionally unchanged'
    InstalledVersionBeforeUpdate = $null
    InstalledVersionAfterUpdate = $null
    InstalledVersionAfterRollback = $null
    UpdatePreservedUserData = $false
    RollbackPreservedUserData = $false
    UserMcmConfigurationUnchangedAfterUninstall = $false
    FormalSavesUnchangedAfterUninstall = $false
    NoGameProcessesDuringUninstall = $false
    IsolatedGameRoot = $overlayRoot
    ModuleDependencyIds = @()
    ModuleDependencyMinimumVersions = @()
    InstalledGameModuleUntouched = $false
    InstalledGameModuleHashBefore = $installedModuleTreeHashBefore
    InstalledGameModuleHashAfter = $null
    UserMcmConfigurationUnchanged = $false
    FormalSaveHashesUnchanged = $false
    IsolatedWorkerCleaned = $false
    PackageTestFilesRemoved = $false
    Failure = $null
}

try {
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $runDirectoryCreated = $true
    foreach ($output in @($firstOutput,$secondOutput)) {
        $resultText = & $HarnessPowerShell -NoProfile -File (Join-Path $stageRoot 'New-ChronicleReleasePackage.ps1') -GameRoot $gameRoot -OutputRoot $output 2>&1 | Out-String
        $generatorExitCode = $LASTEXITCODE
        if ($generatorExitCode -ne 0) { throw "Release package generator failed (exit=$generatorExitCode). $resultText" }
        $receipt = $resultText.Trim() | ConvertFrom-Json
        if (-not (Test-Path -LiteralPath $receipt.PackagePath -PathType Leaf) -or -not (Test-Path -LiteralPath $receipt.ManifestPath -PathType Leaf)) { throw 'Release package generator omitted its package or sidecar manifest.' }
        $packageReceipts += $receipt
    }
    $packageReproducible = ([string]$packageReceipts[0].Sha256 -ceq [string]$packageReceipts[1].Sha256)
    if (-not $packageReproducible) { throw 'Two clean builds from the same committed source did not produce identical package SHA-256 values.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead([string]$packageReceipts[0].PackagePath)
    try {
        $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
        foreach ($entryName in $entryNames) {
            if ($entryName.StartsWith('/') -or $entryName -match '(^|/)\.\.(?:/|$)' -or $entryName -notmatch '^ChronicleFramework/') { throw "Unsafe or unexpected archive path: $entryName" }
        }
        $manifestEntry = $zip.GetEntry('ChronicleFramework/release-manifest.json')
        if (-not $manifestEntry) { throw 'Release archive does not include release-manifest.json.' }
        $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.Encoding]::UTF8)
        try { $packageManifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        $fileRows = @($packageManifest.files)
        if ($fileRows.Count -lt 8) { throw 'Release manifest file inventory is unexpectedly small.' }
        $expectedEntries = @($fileRows | ForEach-Object { 'ChronicleFramework/' + [string]$_.path }) + 'ChronicleFramework/release-manifest.json'
        if (@(Compare-Object ($entryNames | Sort-Object) ($expectedEntries | Sort-Object)).Count -gt 0) { throw 'Archive entries do not exactly match the release manifest file set.' }
        foreach ($row in $fileRows) {
            $entry = $zip.GetEntry('ChronicleFramework/' + [string]$row.path)
            if (-not $entry -or $entry.Length -ne [long]$row.sizeBytes) { throw "Manifest file length mismatch: $($row.path)" }
            $stream = $entry.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
                finally { $sha.Dispose() }
            }
            finally { $stream.Dispose() }
            if ($actualHash -cne [string]$row.sha256) { throw "Manifest file SHA-256 mismatch: $($row.path)" }
        }
        $sourceManifestEntry = $zip.GetEntry('ChronicleFramework/SubModule.xml')
        if (-not $sourceManifestEntry) { throw 'Release archive omits the Bannerlord SubModule.xml.' }
        $reader = [IO.StreamReader]::new($sourceManifestEntry.Open(), [Text.Encoding]::UTF8)
        try { [xml]$packagedModuleManifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ([string]$packagedModuleManifest.Module.Id.value -ne 'ChronicleFramework' -or [string]$packageManifest.moduleId -ne 'ChronicleFramework' -or
            [string]$packageManifest.moduleVersion -ne [string]$packagedModuleManifest.Module.Version.value -or
            [string]$packageManifest.testedGameBuild -ne '1.4.8.119303') { throw 'Release manifest and Native module version metadata do not agree.' }
        $requiredIds = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox')
        $dependencyIds = @($packagedModuleManifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
        foreach ($requiredId in $requiredIds) { if ($requiredId -notin $dependencyIds) { throw "Package dependency manifest omits '$requiredId'." } }
        if (@($fileRows | Where-Object { $_.path -match '(?i)\.pdb$|harness\.local\.json|ChronicleAgentSettings\.json|TestResults|AGENTS\.md' }).Count -gt 0) {
            throw 'Release package contains debug symbols, local settings, Harness results or agent instructions.'
        }
        foreach ($requiredPackagePath in @('ChronicleFramework/bin/Win64_Shipping_Client/ChronicleFramework.dll','ChronicleFramework/AgentHost/ChronicleAgentHost.exe','ChronicleFramework/AgentHost/ChronicleAgentHost.dll','ChronicleFramework/README.txt','ChronicleFramework/LICENSE.txt')) {
            if ($requiredPackagePath -notin $entryNames) { throw "Release archive is missing required player/install file '$requiredPackagePath'." }
        }
        $readmeEntry = $zip.GetEntry('ChronicleFramework/README.txt')
        $readmeReader = [IO.StreamReader]::new($readmeEntry.Open(), [Text.Encoding]::UTF8)
        try { $packageReadme = $readmeReader.ReadToEnd() } finally { $readmeReader.Dispose() }
        if ($packageReadme -notmatch 'close Bannerlord' -or $packageReadme -notmatch 'no hot-update path') { throw 'Player packaging instructions must require closing the game before update/rollback/uninstall and reject hot replacement.' }
        $dependencyMinimumVersions = @($packageManifest.dependencies | ForEach-Object { [pscustomobject]@{ id=$_.id; minimumVersion=$_.minimumVersion; required=[bool]$_.required; installedTestVersion=$_.installedTestVersion } })
        if (@($dependencyMinimumVersions | Where-Object { -not [bool]$_.required -or [string]::IsNullOrWhiteSpace($_.minimumVersion) -or [string]::IsNullOrWhiteSpace($_.installedTestVersion) }).Count -gt 0) { throw 'Every declared module prerequisite must be required and record its minimum and tested installed version.' }
        $evidence.ModuleDependencyIds = $dependencyIds
        $evidence.ModuleDependencyMinimumVersions = $dependencyMinimumVersions
        $evidence.ManifestValidated = $true
    }
    finally { $zip.Dispose() }

    Expand-Archive -LiteralPath ([string]$packageReceipts[0].PackagePath) -DestinationPath $extractRoot -ErrorAction Stop
    New-IsolatedGameRoot -SourceRoot $gameRoot -DestinationRoot $overlayRoot -PackagedModuleRoot (Join-Path $extractRoot 'ChronicleFramework') | Out-Null
    $smokeResult = Invoke-PackagedSmoke -IsolatedRoot $overlayRoot
    $smokePassed = ([bool]$smokeResult.FinishedAll -and [bool]$smokeResult.AssemblyLoaded -and [bool]$smokeResult.LifecycleLoadObserved -and
        [bool]$smokeResult.McmSettingsRegistered -and [bool]$smokeResult.StableAfterFinishedAll -and -not [bool]$smokeResult.CrashDetected -and
        -not [bool]$smokeResult.ProcessExitedUnexpectedly -and 'ChronicleFramework' -in @($smokeResult.ModuleIds) -and
        @($smokeResult.McmButtonPropertyIds).Count -eq 4 -and [string]$smokeResult.GameRoot -eq [IO.Path]::GetFullPath($overlayRoot))
    if (-not $smokePassed) { throw 'The isolated package Smoke did not prove that the archived module loaded and registered the expected MCM settings/buttons.' }
    $gameShutdownDeadline = (Get-Date).AddSeconds(15)
    while (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0 -and (Get-Date) -lt $gameShutdownDeadline) { Start-Sleep -Milliseconds 250 }
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'The isolated Bannerlord process did not exit before package file-maintenance fixtures; preserving the mounted test root.' }
    $isolatedModulesPath = Join-Path $overlayRoot 'Modules'
    $isolatedChroniclePath = Join-Path $isolatedModulesPath 'ChronicleFramework'
    if (-not (Test-Path -LiteralPath (Join-Path $isolatedChroniclePath 'SubModule.xml') -PathType Leaf)) { throw 'The isolated release module is missing before uninstall verification.' }
    [xml]$installedManifestBeforeUpdate = Get-Content -LiteralPath (Join-Path $isolatedChroniclePath 'SubModule.xml') -Encoding UTF8
    $versionBeforeUpdate = [string]$installedManifestBeforeUpdate.Module.Version.value
    if ($versionBeforeUpdate -ne 'v0.1.0') { throw "Synthetic update fixture expected package version v0.1.0; found $versionBeforeUpdate." }
    $oldInstalledModuleHash = Get-DirectorySnapshotSha256 $isolatedChroniclePath

    $updateFixtureModule = Join-Path $runRoot 'SyntheticUpdateFixture\ChronicleFramework'
    New-Item -ItemType Directory -Path (Split-Path -Parent $updateFixtureModule) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $extractRoot 'ChronicleFramework') -Destination $updateFixtureModule -Recurse
    $updateSubModulePath = Join-Path $updateFixtureModule 'SubModule.xml'
    [xml]$updateManifest = Get-Content -LiteralPath $updateSubModulePath -Encoding UTF8
    $updateManifest.Module.Version.value = 'v0.1.1'
    $updateManifest.Save($updateSubModulePath)
    $updateReleaseManifestPath = Join-Path $updateFixtureModule 'release-manifest.json'
    $updateReleaseManifest = Get-Content -LiteralPath $updateReleaseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $updateReleaseManifest.moduleVersion = 'v0.1.1'
    $subModuleFileRow = @($updateReleaseManifest.files | Where-Object { $_.path -eq 'SubModule.xml' })
    if ($subModuleFileRow.Count -ne 1) { throw 'Synthetic update fixture could not locate its SubModule.xml file-hash entry.' }
    $subModuleFileRow[0].sizeBytes = (Get-Item -LiteralPath $updateSubModulePath).Length
    $subModuleFileRow[0].sha256 = (Get-FileHash -LiteralPath $updateSubModulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($updateReleaseManifestPath, ($updateReleaseManifest | ConvertTo-Json -Depth 10) + "`r`n", [Text.UTF8Encoding]::new($false))

    Assert-GameClosedForModuleFileChange 'update'
    Remove-IsolatedTree -Path $isolatedChroniclePath -AllowedParent $isolatedModulesPath -ExpectedLeafPattern '^ChronicleFramework$'
    Copy-Item -LiteralPath $updateFixtureModule -Destination $isolatedChroniclePath -Recurse
    [xml]$installedManifestAfterUpdate = Get-Content -LiteralPath (Join-Path $isolatedChroniclePath 'SubModule.xml') -Encoding UTF8
    $evidence.InstalledVersionBeforeUpdate = $versionBeforeUpdate
    $evidence.InstalledVersionAfterUpdate = [string]$installedManifestAfterUpdate.Module.Version.value
    if ($evidence.InstalledVersionAfterUpdate -ne 'v0.1.1' -or (Get-DirectorySnapshotSha256 $isolatedChroniclePath) -ceq $oldInstalledModuleHash) {
        throw 'Synthetic package update did not install the newer manifest version and corresponding file hash.'
    }
    $evidence.UpdatePreservedUserData = (Test-McmConfigUnchanged) -and (Test-FormalSaveSetUnchanged $saveHashesBefore)
    if (-not $evidence.UpdatePreservedUserData) { throw 'Synthetic package update changed user MCM settings or Campaign saves.' }

    Assert-GameClosedForModuleFileChange 'rollback'
    Remove-IsolatedTree -Path $isolatedChroniclePath -AllowedParent $isolatedModulesPath -ExpectedLeafPattern '^ChronicleFramework$'
    Copy-Item -LiteralPath (Join-Path $extractRoot 'ChronicleFramework') -Destination $isolatedChroniclePath -Recurse
    [xml]$installedManifestAfterRollback = Get-Content -LiteralPath (Join-Path $isolatedChroniclePath 'SubModule.xml') -Encoding UTF8
    $evidence.InstalledVersionAfterRollback = [string]$installedManifestAfterRollback.Module.Version.value
    $evidence.RollbackPreservedUserData = (Test-McmConfigUnchanged) -and (Test-FormalSaveSetUnchanged $saveHashesBefore)
    if ($evidence.InstalledVersionAfterRollback -ne $versionBeforeUpdate -or (Get-DirectorySnapshotSha256 $isolatedChroniclePath) -cne $oldInstalledModuleHash -or -not $evidence.RollbackPreservedUserData) {
        throw 'Rollback did not restore the original package files/version while preserving user data.'
    }
    $evidence.UpdateRollbackCycleVerified = $true

    Assert-GameClosedForModuleFileChange 'uninstall'
    Remove-IsolatedTree -Path $isolatedChroniclePath -AllowedParent $isolatedModulesPath -ExpectedLeafPattern '^ChronicleFramework$'
    $evidence.UninstallRemovedOnlyChronicleModule = -not (Test-Path -LiteralPath $isolatedChroniclePath)
    $evidence.RequiredModulesRemainAfterUninstall = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox') |
        ForEach-Object { Test-Path -LiteralPath (Join-Path $isolatedModulesPath ($_ + '\SubModule.xml')) -PathType Leaf } |
        Where-Object { -not $_ } | Measure-Object | ForEach-Object { $_.Count -eq 0 }
    $evidence.UserMcmConfigurationUnchangedAfterUninstall = Test-McmConfigUnchanged
    $evidence.FormalSavesUnchangedAfterUninstall = Test-FormalSaveSetUnchanged $saveHashesBefore
    $evidence.NoGameProcessesDuringUninstall = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
    if (-not $evidence.UpdateRollbackCycleVerified -or -not $evidence.UninstallRemovedOnlyChronicleModule -or -not $evidence.RequiredModulesRemainAfterUninstall -or
        -not $evidence.UserMcmConfigurationUnchangedAfterUninstall -or -not $evidence.FormalSavesUnchangedAfterUninstall -or -not $evidence.NoGameProcessesDuringUninstall) {
        throw 'Simulated uninstall did not remove only the Chronicle module folder while preserving prerequisites, user settings and Campaign saves.'
    }
    $evidence.PackageReproducible = $packageReproducible
    $evidence.PackageSha256 = [string]$packageReceipts[0].Sha256
    $evidence.IsolatedSmokePassed = $true
    $evidence.UserMcmConfigurationUnchanged = if ($mcmHashBefore) { (Test-Path -LiteralPath $mcmSettings -PathType Leaf) -and (Get-FileHash -LiteralPath $mcmSettings -Algorithm SHA256).Hash -ceq $mcmHashBefore } else { -not (Test-Path -LiteralPath $mcmSettings -PathType Leaf) }
    $saveHashesAfter = @{}
    if (Test-Path -LiteralPath $sourceCampaignDirectory -PathType Container) {
        Get-ChildItem -LiteralPath $sourceCampaignDirectory -File -Filter '*.sav' | ForEach-Object { $saveHashesAfter[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
    $evidence.FormalSaveHashesUnchanged = ($saveHashesBefore.Count -eq $saveHashesAfter.Count -and @($saveHashesBefore.Keys | Where-Object { -not $saveHashesAfter.ContainsKey($_) -or $saveHashesAfter[$_] -cne $saveHashesBefore[$_] }).Count -eq 0)
    if (-not $evidence.UserMcmConfigurationUnchanged -or -not $evidence.FormalSaveHashesUnchanged) { throw 'Isolated release Smoke changed a user MCM setting or formal Campaign save.' }
    $installedModuleTreeHashAfter = Get-DirectorySnapshotSha256 $installedModulePath
    $evidence.InstalledGameModuleHashAfter = $installedModuleTreeHashAfter
    $evidence.InstalledGameModuleUntouched = $installedModuleTreeHashAfter -ceq $installedModuleTreeHashBefore
    $evidence.Passed = $evidence.InstalledGameModuleUntouched
    if (-not $evidence.Passed) { throw 'The installed Chronicle module changed during isolated package validation.' }
}
catch { $evidence.Failure = $_.Exception.Message }
finally {
    if ($engineConfigOriginallyExists) { [IO.File]::WriteAllBytes($engineConfig, $engineConfigBytes) }
    elseif (Test-Path -LiteralPath $engineConfig -PathType Leaf) { Remove-Item -LiteralPath $engineConfig -Force }
    try {
        $activeGameProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
        if ($activeGameProcesses.Count -eq 0) {
            Remove-IsolatedTree -Path $overlayRoot -AllowedParent $runRoot -ExpectedLeafPattern '^IsolatedGameRoot$'
            $evidence.IsolatedWorkerCleaned = $true
        }
        else {
            $evidence.IsolatedWorkerCleaned = $false
            $evidence.PackageTestFilesRemoved = $false
            if (-not $evidence.Failure) { $evidence.Failure = 'A Bannerlord process is still active; isolated package files were preserved rather than deleting a mounted game tree.' }
        }
        if ($activeGameProcesses.Count -eq 0 -and (Test-Path -LiteralPath $runRoot)) {
            $runFull = [IO.Path]::GetFullPath($runRoot)
            $allowed = [IO.Path]::GetFullPath($buildCacheRoot).TrimEnd('\') + '\'
            if (-not $runFull.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($runFull) -notmatch '^test-[0-9a-f]{32}$') { throw 'Refusing package test cleanup outside its generated D: root.' }
            Remove-IsolatedTree -Path $runFull -AllowedParent $buildCacheRoot -ExpectedLeafPattern '^test-[0-9a-f]{32}$'
        }
        $evidence.PackageTestFilesRemoved = -not (Test-Path -LiteralPath $runRoot)
    }
    catch { if (-not $evidence.Failure) { $evidence.Failure = "Cleanup failed: $($_.Exception.Message)" }; $evidence.Passed = $false }
}
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $harnessTemp 'AgentHostReleasePackageResult.json') -Encoding UTF8
$evidence | ConvertTo-Json -Depth 10
if (-not $evidence.Passed -or -not $evidence.PackageReproducible -or -not $evidence.ManifestValidated -or -not $evidence.IsolatedSmokePassed -or -not $evidence.UpdateRollbackCycleVerified -or
    -not $evidence.UninstallRemovedOnlyChronicleModule -or -not $evidence.RequiredModulesRemainAfterUninstall -or
    -not $evidence.UserMcmConfigurationUnchangedAfterUninstall -or -not $evidence.FormalSavesUnchangedAfterUninstall -or
    -not $evidence.NoGameProcessesDuringUninstall -or -not $evidence.IsolatedWorkerCleaned -or -not $evidence.PackageTestFilesRemoved) { exit 1 }
