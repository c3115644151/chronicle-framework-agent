#Requires -Version 7.0

# Build stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Build' -Action {
    $runningBannerlordClients = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($runningBannerlordClients.Count -gt 0) {
        $runningClientSummary = ($runningBannerlordClients | ForEach-Object { "$($_.ProcessName)#$($_.Id)" }) -join ', '
        throw "Refusing to build or deploy ChronicleFramework while a Bannerlord client is running ($runningClientSummary). Close the game normally and retry; Harness will not stop a live client or overwrite its loaded DLL."
    }
    $mainlinePath = Join-Path $docsRoot 'MAINLINE.md'
    $mainlineText = Get-Content -LiteralPath $mainlinePath -Raw -Encoding UTF8
    $researchGateReady = $mainlineText -match '(?m)^Research Gate: \*\*READY\*\*\s*$'
    $implementationGateReady = $mainlineText -match '(?m)^Implementation Gate: \*\*READY\*\*\s*$'
    $moduleDll = Join-Path $gameRoot 'Modules\ChronicleFramework\bin\Win64_Shipping_Client\ChronicleFramework.dll'
    $sourceFiles = @(Get-ChildItem -LiteralPath $modRoot -File -Filter '*.cs')
    $changedFeatureSources = if (Test-Path -LiteralPath $moduleDll) {
        @($sourceFiles | Where-Object { $_.LastWriteTimeUtc -gt (Get-Item -LiteralPath $moduleDll).LastWriteTimeUtc })
    } else { $sourceFiles }
    $subModuleSource = Join-Path $modRoot 'SubModule.cs'
    $diagnosticSourceHash = if (Test-Path -LiteralPath $subModuleSource) { Get-ChronicleCanonicalFileSha256 -LiteralPath $subModuleSource } else { '' }
    $readiness = Get-ChronicleResearchReadiness -ResearchReady $researchGateReady -ImplementationReady $implementationGateReady -ChangedFeatureSources @($changedFeatureSources | ForEach-Object Name) -AuditedHarnessDiagnosticSha256 $diagnosticSourceHash
    if (-not $readiness.Allowed) { throw $readiness.Reason }
    $sourceManifestHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
    $runtimeManifestHash = if (Test-Path -LiteralPath $manifestPath) { (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash } else { '' }
    if ($sourceManifestHash -ne $runtimeManifestHash) { Copy-Item -LiteralPath $sourceManifestPath -Destination $manifestPath -Force }
    $sourceModuleData = Join-Path $modulePackageRoot 'ModuleData'
    $runtimeModuleData = Join-Path (Split-Path -Parent $manifestPath) 'ModuleData'
    if (-not (Test-Path -LiteralPath $sourceModuleData -PathType Container)) { throw 'Chronicle ModuleData source is missing.' }
    New-Item -ItemType Directory -Path $runtimeModuleData -Force | Out-Null
    foreach ($moduleDataEntry in Get-ChildItem -LiteralPath $sourceModuleData -Force) {
        Copy-Item -LiteralPath $moduleDataEntry.FullName -Destination $runtimeModuleData -Recurse -Force
    }
    $modAssetsPath = Join-Path (Split-Path -Parent $projectPath) 'obj\project.assets.json'
    if (-not (Test-Path -LiteralPath $modAssetsPath)) {
        $modRestoreOutput = & dotnet restore $projectPath "-p:ChronicleGameRoot=$gameRoot" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Mod project restore failed with exit code $LASTEXITCODE." + [char]10 + $modRestoreOutput }
    }
    $buildOutput = & dotnet build $projectPath --configuration Release --no-restore "-p:ChronicleGameRoot=$gameRoot" 2>&1 | Out-String
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -ne 0) { throw "Build failed with exit code $buildExitCode.`n$buildOutput" }
    $agentHostBuildOutput = & dotnet build $agentHostProjectPath --configuration Release 2>&1 | Out-String
    $agentHostBuildExitCode = $LASTEXITCODE
    $agentHostNuGetAuditFallbackUsed = $false
    if ($agentHostBuildExitCode -ne 0 -and $agentHostBuildOutput -match 'NU1900') {
        $agentHostProjectDirectory = Split-Path -Parent $agentHostProjectPath
        $agentHostProjectXml = [xml](Get-Content -LiteralPath $agentHostProjectPath -Raw -Encoding UTF8)
        $agentHostPackageReferences = @($agentHostProjectXml.SelectNodes('//PackageReference'))
        $agentHostPackageLockPath = Join-Path $agentHostProjectDirectory 'packages.lock.json'
        $pinnedHostPackage = ($agentHostPackageReferences.Count -eq 1 -and
            $agentHostPackageReferences[0].GetAttribute('Include') -ceq 'Microsoft.ML.Tokenizers' -and
            $agentHostPackageReferences[0].GetAttribute('Version') -ceq '[2.0.1]' -and
            (Test-Path -LiteralPath $agentHostPackageLockPath -PathType Leaf))
        if (-not $pinnedHostPackage) {
            throw "NuGet vulnerability feed returned NU1900; the offline audit fallback is allowed only for the single locked Microsoft.ML.Tokenizers 2.0.1 Host dependency. $agentHostBuildOutput"
        }
        $fallbackRestoreOutput = & dotnet restore $agentHostProjectPath --locked-mode -p:NuGetAudit=false 2>&1 | Out-String
        $fallbackRestoreExitCode = $LASTEXITCODE
        if ($fallbackRestoreExitCode -ne 0) { throw "NuGet audit metadata was unavailable and locked local dependency restore failed (exit=$fallbackRestoreExitCode).`n$fallbackRestoreOutput" }
        $fallbackHostBuildOutput = & dotnet build $agentHostProjectPath --configuration Release --no-restore 2>&1 | Out-String
        $agentHostBuildExitCode = $LASTEXITCODE
        $agentHostBuildOutput = "Initial Host build could not reach the vulnerability feed (NU1900); the project has one pinned lockfile dependency, so restore retried in locked mode without the unavailable audit endpoint.`n$fallbackRestoreOutput`nHost build after locked restore:`n$fallbackHostBuildOutput"
        $agentHostNuGetAuditFallbackUsed = $true
    }
    if ($agentHostBuildExitCode -ne 0) { throw "Local Agent Host build failed with exit code $agentHostBuildExitCode.`n$agentHostBuildOutput" }
    [ordered]@{ gameModBuild = $buildOutput; localAgentHostBuild = $agentHostBuildOutput; nugetAuditFallbackUsed = $agentHostNuGetAuditFallbackUsed } | ConvertTo-Json -Depth 4
}
