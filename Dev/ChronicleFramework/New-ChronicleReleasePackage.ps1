[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$OutputRoot = 'D:\ChronicleFramework\BuildCache\ReleasePackages',
    [switch]$KeepFailedStage
)

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
$repositoryRoot = (& git -C $harnessRoot rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'Could not resolve the Chronicle Framework repository root.' }
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot)
$trackedChanges = (& git -C $repositoryRoot status --porcelain --untracked-files=no 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect tracked source state.' }
$sourceTreeClean = [string]::IsNullOrWhiteSpace($trackedChanges)
$sourceCommit = (& git -C $repositoryRoot rev-parse HEAD 2>$null | Out-String).Trim()
$sourceBranch = (& git -C $repositoryRoot branch --show-current 2>$null | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $localSettingsPath = Join-Path $harnessRoot 'harness.local.json'
    if (-not (Test-Path -LiteralPath $localSettingsPath -PathType Leaf)) { throw 'GameRoot is required unless the local Harness settings file is present.' }
    $GameRoot = [string](Get-Content -LiteralPath $localSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).gameRoot
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$repoPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($OutputRoot.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Release packages and build staging must remain outside the source repository.' }
if ($OutputRoot -notmatch '^D:\\') { throw 'Release staging must be located on D:.' }

$moduleSource = Join-Path $repositoryRoot 'Modules\ChronicleFramework\SubModule.xml'
$moduleProject = Join-Path $harnessRoot 'ChronicleFramework.csproj'
$hostProject = Join-Path $harnessRoot 'AgentHost\ChronicleAgentHost.csproj'
$gameExecutable = Join-Path $GameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) { throw 'GameRoot is not a Bannerlord installation.' }
foreach ($path in @($moduleSource, $moduleProject, $hostProject)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required source file is missing: $path" } }

[xml]$sourceManifest = Get-Content -LiteralPath $moduleSource -Raw -Encoding UTF8
$moduleId = [string]$sourceManifest.Module.Id.value
$moduleVersion = [string]$sourceManifest.Module.Version.value
if ($moduleId -ne 'ChronicleFramework' -or $moduleVersion -ne 'v0.1.0') { throw "Unexpected release module identity/version: $moduleId $moduleVersion" }
$dependencies = @($sourceManifest.Module.DependedModules.DependedModule | ForEach-Object {
    [pscustomobject]@{ id = [string]$_.Id; minimumVersion = [string]$_.DependentVersion; required = ([string]$_.Optional -ne 'true') }
})
$requiredDependencyIds = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox')
if (@($requiredDependencyIds | Where-Object { $_ -notin $dependencies.id }).Count -gt 0) { throw 'The source module manifest omits one or more required direct prerequisites.' }
if (@($dependencies | Where-Object { -not $_.required }).Count -gt 0) { throw 'Every release prerequisite must be non-optional in the Native module manifest.' }
foreach ($dependency in $dependencies) {
    $dependencyManifestPath = Join-Path $GameRoot ("Modules\{0}\SubModule.xml" -f $dependency.id)
    if (-not (Test-Path -LiteralPath $dependencyManifestPath -PathType Leaf)) { throw "Installed test prerequisite is missing: $($dependency.id)" }
    [xml]$dependencyManifest = Get-Content -LiteralPath $dependencyManifestPath -Raw -Encoding UTF8
    $installedVersionText = ([string]$dependencyManifest.Module.Version.value).TrimStart('v')
    $minimumVersionText = $dependency.minimumVersion.TrimStart('v')
    if ([version]$installedVersionText -lt [version]$minimumVersionText) { throw "Installed $($dependency.id) version $installedVersionText is below declared minimum $minimumVersionText." }
    $dependency | Add-Member -NotePropertyName installedTestVersion -NotePropertyValue ([string]$dependencyManifest.Module.Version.value)
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$packageName = 'ChronicleFramework-0.1.0.zip'
$archivePath = Join-Path $OutputRoot $packageName
$manifestSidecarPath = $archivePath + '.manifest.json'
$checksumPath = $archivePath + '.sha256'
foreach ($existingPath in @($archivePath, $manifestSidecarPath, $checksumPath)) {
    if (Test-Path -LiteralPath $existingPath) { throw "Release output already exists; use a fresh output directory or bump the package version: $existingPath" }
}

$stageId = [Guid]::NewGuid().ToString('N')
$stageRoot = Join-Path $OutputRoot ('.stage-' + $stageId)
$moduleStage = Join-Path $stageRoot 'ChronicleFramework'
$moduleBinaryDirectory = Join-Path $moduleStage 'bin\Win64_Shipping_Client'
$hostDirectory = Join-Path $moduleStage 'AgentHost'
$hostBuildRoot = Join-Path $stageRoot 'host-build'
New-Item -ItemType Directory -Path $moduleBinaryDirectory,$hostDirectory,$hostBuildRoot -Force | Out-Null
$keepStage = $false
$previousEnvironment = @{}
foreach ($name in @('NUGET_PACKAGES','HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy')) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

try {
    Copy-Item -LiteralPath $moduleSource -Destination (Join-Path $moduleStage 'SubModule.xml')
    $moduleBuildArguments = @('build',$moduleProject,'--configuration','Release','--no-restore',
        "-p:ChronicleGameRoot=$GameRoot", "-p:OutputPath=$moduleBinaryDirectory\", '-p:AppendTargetFrameworkToOutputPath=false')
    $moduleBuildLog = & dotnet @moduleBuildArguments 2>&1 | Out-String
    $moduleBuildExitCode = $LASTEXITCODE
    if ($moduleBuildExitCode -ne 0) { throw "Chronicle module build failed (exit=$moduleBuildExitCode). $moduleBuildLog" }
    $moduleDll = Join-Path $moduleBinaryDirectory 'ChronicleFramework.dll'
    if (-not (Test-Path -LiteralPath $moduleDll -PathType Leaf)) { throw 'The module build did not produce ChronicleFramework.dll in the release staging directory.' }
    $moduleAssemblyVersion = [System.Reflection.AssemblyName]::GetAssemblyName($moduleDll).Version.ToString()
    if ($moduleAssemblyVersion -ne '0.1.0.0') { throw "Module AssemblyVersion '$moduleAssemblyVersion' does not match release contract 0.1.0.0." }

    $nugetRoot = 'D:\ChronicleFramework\BuildCache\NuGetPackages'
    New-Item -ItemType Directory -Path $nugetRoot -Force | Out-Null
    [Environment]::SetEnvironmentVariable('NUGET_PACKAGES', $nugetRoot, 'Process')
    $proxyUri = 'http://127.0.0.1:7890'
    $proxyReady = Test-NetConnection -ComputerName '127.0.0.1' -Port 7890 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($proxyReady) {
        foreach ($name in @('HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy')) { [Environment]::SetEnvironmentVariable($name, $proxyUri, 'Process') }
    }
    $hostPublishArguments = @('publish',$hostProject,'--configuration','Release','--runtime','win-x64','--self-contained','true',
        '-p:UseAppHost=true', "-p:BaseOutputPath=$hostBuildRoot\", '-o', $hostDirectory)
    $hostPublishLog = & dotnet @hostPublishArguments 2>&1 | Out-String
    $hostPublishExitCode = $LASTEXITCODE
    if ($hostPublishExitCode -ne 0 -and $hostPublishLog -match 'NU1900') {
        [xml]$projectXml = Get-Content -LiteralPath $hostProject -Raw -Encoding UTF8
        if (@($projectXml.Project.ItemGroup.PackageReference).Count -gt 0) { throw "NuGet audit feed failed while the Host has package dependencies; refusing fallback. $hostPublishLog" }
        $hostPublishArguments += '-p:NuGetAudit=false'
        $auditFallbackLog = & dotnet @hostPublishArguments 2>&1 | Out-String
        $hostPublishExitCode = $LASTEXITCODE
        $hostPublishLog += "`nNU1900 audit metadata was unreachable; dependencies remained enabled and publish retried without the audit endpoint.`n$auditFallbackLog"
    }
    if ($hostPublishExitCode -ne 0) { throw "Self-contained Host publish failed (exit=$hostPublishExitCode). $hostPublishLog" }
    $hostExe = Join-Path $hostDirectory 'ChronicleAgentHost.exe'
    $hostDll = Join-Path $hostDirectory 'ChronicleAgentHost.dll'
    foreach ($required in @($hostExe,$hostDll,(Join-Path $hostDirectory 'hostfxr.dll'),(Join-Path $hostDirectory 'hostpolicy.dll'),(Join-Path $hostDirectory 'coreclr.dll'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Self-contained Host staging is missing required runtime file: $required" }
    }
    Get-ChildItem -LiteralPath $moduleStage -Recurse -File -Filter '*.pdb' | Remove-Item -Force
    if (@(Get-ChildItem -LiteralPath $moduleStage -Recurse -File -Filter 'ChronicleAgentSettings.json').Count -gt 0) { throw 'User MCM settings must never be included in the release package.' }

    $readme = @'
Chronicle Framework v0.1.0 - private test build

Supported/tested game: Mount & Blade II: Bannerlord 1.4.8.119303. Other game versions and mod combinations are not declared compatible.

Install: extract this archive and place the top-level ChronicleFramework folder under the game's Modules directory. Enable the required modules in the order reported by the game's module manager; Chronicle's SubModule.xml declares the required modules and minimum versions.

The package contains the Chronicle game module and its self-contained Windows x64 Agent Host. It does not include Ollama, model weights, user MCM settings, saves, or development Harness files. Configure an already installed local loopback Ollama service in Chronicle's MCM settings before starting the Agent.

This is not a public release and has not been tested through a third-party mod manager installation flow. The W7 Epic remains the final player installation/launch acceptance.
'@
    $license = @'
Private test package notice

Copyright (c) 2026 Chronicle Framework contributors. All rights reserved.

No public software license has been selected for this test build. No public redistribution permission is granted. Do not upload or redistribute this package. A public license decision is reserved for the project owner before any public release.
'@
    [IO.File]::WriteAllText((Join-Path $moduleStage 'README.txt'), $readme.Trim() + "`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $moduleStage 'LICENSE.txt'), $license.Trim() + "`r`n", [Text.UTF8Encoding]::new($false))

    $files = @(Get-ChildItem -LiteralPath $moduleStage -Recurse -File | Sort-Object { $_.FullName.Substring($moduleStage.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar,'/') })
    $fileManifest = @($files | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($moduleStage.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar,'/')
            sizeBytes = [long]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $hostAssemblyVersion = [System.Reflection.AssemblyName]::GetAssemblyName($hostDll).Version.ToString()
    $manifest = [ordered]@{
        schemaVersion = 1
        moduleId = $moduleId
        moduleVersion = $moduleVersion
        moduleAssemblyVersion = $moduleAssemblyVersion
        hostProduct = 'ChronicleAgentHost'
        hostAssemblyVersion = $hostAssemblyVersion
        hostRuntime = 'Self-contained Windows x64 / .NET 8'
        supportedGameVersion = '1.4.8'
        testedGameBuild = '1.4.8.119303'
        sourceCommit = $sourceCommit
        sourceBranch = $sourceBranch
        sourceTreeClean = $sourceTreeClean
        dependencies = @($dependencies | ForEach-Object { [ordered]@{ id=$_.id; minimumVersion=$_.minimumVersion; required=[bool]$_.required; installedTestVersion=$_.installedTestVersion } })
        licenseState = 'Private test build; no public license selected; redistribution not authorized'
        manifestHashScope = 'files excludes release-manifest.json to avoid recursive hashing'
        files = $fileManifest
    }
    $manifestPath = Join-Path $moduleStage 'release-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10) + "`r`n", [Text.UTF8Encoding]::new($false))

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipFile = [IO.File]::Open($archivePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($zipFile, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $archiveFiles = @(Get-ChildItem -LiteralPath $moduleStage -Recurse -File | Sort-Object { $_.FullName.Substring($moduleStage.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar,'/') })
            foreach ($file in $archiveFiles) {
                $relativePath = $file.FullName.Substring($moduleStage.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar,'/')
                $entry = $archive.CreateEntry("ChronicleFramework/$relativePath", [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
                $input = [IO.File]::OpenRead($file.FullName)
                try { $output = $entry.Open(); try { $input.CopyTo($output) } finally { $output.Dispose() } }
                finally { $input.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $zipFile.Dispose() }
    $zipHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($manifestSidecarPath, (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($checksumPath, "$zipHash  $packageName`r`n", [Text.UTF8Encoding]::new($false))
    $keepStage = $false
    [pscustomobject]@{
        PackagePath = $archivePath
        PackageName = $packageName
        Sha256 = $zipHash
        ManifestPath = $manifestSidecarPath
        FileCount = $fileManifest.Count
        ModuleId = $moduleId
        ModuleVersion = $moduleVersion
        HostVersion = $hostAssemblyVersion
        SourceCommit = $sourceCommit
        GameVersion = '1.4.8.119303'
        StageRemoved = $true
    } | ConvertTo-Json -Depth 8 -Compress
}
catch {
    if ($KeepFailedStage) { $keepStage = $true }
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    throw
}
finally {
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
    $stageFull = [IO.Path]::GetFullPath($stageRoot)
    $outputPrefix = $OutputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $stageFull.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($stageFull) -notmatch '^\.stage-[0-9a-f]{32}$') { throw 'Refusing to clean a staging directory outside the generated package root.' }
    if (-not $keepStage -and (Test-Path -LiteralPath $stageFull -PathType Container)) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
}
