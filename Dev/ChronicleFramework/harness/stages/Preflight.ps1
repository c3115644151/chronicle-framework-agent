#Requires -Version 7.0

# Preflight stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Preflight' -Action {
    if (-not (Test-Path $gameExe)) { throw "Game executable not found: $gameExe" }
    $targetGameBranch = 'v1.4.8'
    $gameBranch = Assert-ChronicleSteamGameBranch -GameRoot $gameRoot -RequiredBranch $targetGameBranch
    if (-not (Test-Path $projectPath)) { throw "Project not found: $projectPath" }
    if (-not (Test-Path $manifestPath)) { throw "Manifest not found: $manifestPath" }
    if (-not (Test-Path $sourceManifestPath)) { throw "Version-controlled manifest not found: $sourceManifestPath" }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet was not found on PATH.' }
    if (-not (Get-Command ilspycmd -ErrorAction SilentlyContinue)) { throw 'ilspycmd was not found on PATH.' }
    $templateList = dotnet new list 2>&1 | Out-String
    if ($templateList -notmatch 'blmodfx') { throw 'Bannerlord.Templates blmodfx template was not found.' }
    & $HarnessPowerShell -NoProfile -File $saveModuleMetadataTestScript
    if ($LASTEXITCODE -ne 0) { throw "Save module metadata test failed with exit code $LASTEXITCODE." }
    [xml]$manifest = Get-Content $sourceManifestPath
    if ([string]$manifest.Module.Id.value -ne 'ChronicleFramework') { throw 'Unexpected module id.' }
    $dependencies = @($manifest.Module.DependedModules.DependedModule | ForEach-Object { [string]$_.Id })
    foreach ($dependency in @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','SandBox')) {
        if ($dependency -notin $dependencies) {
            throw "Missing dependency: $dependency"
        }
    }
    $moduleIds = @(
        'Bannerlord.Harmony',
        'Bannerlord.ButterLib',
        'Bannerlord.UIExtenderEx',
        'Bannerlord.MBOptionScreen',
        'Native',
        'SandBoxCore',
        'CustomBattle',
        'SandBox',
        'StoryMode',
        'BirthAndDeath',
        'ChronicleFramework'
    )
    $moduleVersions = @($moduleIds | ForEach-Object {
        $moduleId = $_
        $moduleDirectory = Get-ChildItem (Join-Path $gameRoot 'Modules') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'SubModule.xml') } |
            Where-Object {
                try { ([xml](Get-Content (Join-Path $_.FullName 'SubModule.xml'))).Module.Id.value -eq $moduleId } catch { $false }
            } |
            Select-Object -First 1
        if (-not $moduleDirectory) { throw "Module manifest not found for id: $moduleId" }
        [xml]$moduleManifest = Get-Content (Join-Path $moduleDirectory.FullName 'SubModule.xml')
        [pscustomobject]@{
            Id = $moduleId
            Directory = $moduleDirectory.Name
            Version = [string]$moduleManifest.Module.Version.value
        }
    })
    $gameFileVersion = (Get-Item $gameExe).VersionInfo.FileVersion
    $packageInfoText = [string](Get-Content (Join-Path $gameRoot 'package_info.txt') -Raw)
    $compileChangeset = if ($packageInfoText -match 'Compile Changeset:\s*(\d+)') { $Matches[1] } else { $null }
    [pscustomobject]@{
        GameExecutable = $gameExe
        TargetGameBranch = $gameBranch.Branch
        SteamBuildId = $gameBranch.BuildId
        SteamManifest = $gameBranch.ManifestPath
        GameFileVersion = $gameFileVersion
        CompileChangeset = $compileChangeset
        Manifest = $manifestPath
        SourceManifest = $sourceManifestPath
        RuntimeManifestMatchesSource = ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash)
        ModuleVersion = [string]$manifest.Module.Version.value
        ModuleSet = $moduleVersions
        Toolchain = @('dotnet', 'ilspycmd', 'Bannerlord.Templates:blmodfx')
        PackageInfoHint = $packageInfoText
    } | ConvertTo-Json -Depth 8
}
