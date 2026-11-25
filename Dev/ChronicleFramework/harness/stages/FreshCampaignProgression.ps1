#Requires -Version 7.0

# FreshCampaignProgression stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'FreshCampaignProgression' -Action {
    $attempts = @()
    $finalResult = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $attemptTemp = Join-Path $harnessTempDirectory "FreshCampaignProgressionAttempt$attempt"
        New-Item -ItemType Directory -Path $attemptTemp -Force | Out-Null
        $previousTemp = $env:CHRONICLE_HARNESS_TEMP
        $env:CHRONICLE_HARNESS_TEMP = $attemptTemp
        try {
            $testOutput = & $HarnessPowerShell -NoProfile -File $freshCampaignScript -ValidateRecruitmentProgression 2>&1 | Out-String
            $testExitCode = $LASTEXITCODE
        }
        finally { $env:CHRONICLE_HARNESS_TEMP = $previousTemp }
        try { $testResult = $testOutput | ConvertFrom-Json }
        catch { throw "Fresh campaign attempt $attempt returned invalid JSON (exit=$testExitCode): $testOutput" }
        $rglTail = @()
        if ($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog)) {
            try {
                $rglLogLines = @(Get-Content -LiteralPath $testResult.RglLog -Tail 8 -ErrorAction Stop)
                $rglTail = @(ConvertTo-ChronicleLogTail -Lines $rglLogLines)
            }
            catch { $rglTail = @([pscustomobject]@{ text = "RGL tail unavailable: $($_.Exception.Message)" }) }
        }
        $startupAssessment = Get-ChronicleStartupAssessment -Attempt $attempt -GameStarted ([bool]$testResult.GameStarted) -NativeNewCampaignRequested ([bool]$testResult.NativeNewCampaignRequested) -CrashDetected ([bool]$testResult.CrashDetected) -CrashWindowTitle ([string]$testResult.CrashWindowTitle) -SaveDirectoryMetadataUnchanged ([bool]$testResult.SaveDirectoryMetadataUnchanged) -RglLogExists ([bool]($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog)))
        $attemptSummary = [ordered]@{
            attempt = $attempt
            exitCode = $testExitCode
            passed = [bool]$testResult.Passed
            gameStarted = [bool]$testResult.GameStarted
            characterCreationCompleted = [bool]$testResult.CharacterCreationCompleted
            nativeNewCampaignRequested = [bool]$testResult.NativeNewCampaignRequested
            gameProcessId = $testResult.GameProcessId
            crashWindowTitle = [string]$testResult.CrashWindowTitle
            crashDetected = [bool]$testResult.CrashDetected
            crashWindowCapture = $testResult.CrashWindowCapture
            crashWindowCaptureError = [string]$testResult.CrashWindowCaptureError
            crashWindowCaptureVideoRetained = [bool]$testResult.CrashWindowCaptureVideoRetained
            crashExceptionPath = [string]$testResult.CrashExceptionPath
            crashExceptionCaptured = [bool]$testResult.CrashExceptionCaptured
            crashFaultAddress = [string]$testResult.CrashFaultAddress
            crashFaultModule = [string]$testResult.CrashFaultModule
            crashModuleInventory = $testResult.CrashModuleInventory
            crashModuleCaptureError = [string]$testResult.CrashModuleCaptureError
            startupClassification = $startupAssessment.Classification
            rglLogPath = [string]$testResult.RglLog
            rglLogExists = [bool]($testResult.RglLog -and (Test-Path -LiteralPath $testResult.RglLog))
            rglTail = $rglTail
            progressionFailureDetail = [string]$testResult.RecruitmentProgressionError
            freshClanRenown = $testResult.ClanRenown
            recruitmentProgression = $testResult.RecruitmentProgression
            progressionSaveCycleVerified = [bool]($testResult.RecruitmentProgression -and $testResult.RecruitmentProgression.DisposableSaveName -and $testResult.RecruitmentProgression.Passed)
            saveDirectoryUnchanged = [bool]$testResult.SaveDirectoryMetadataUnchanged
            evidenceDirectory = $attemptTemp
        }
        $attempts += $attemptSummary
        $attemptSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $attemptTemp 'attempt-summary.json') -Encoding UTF8
        $finalResult = $testResult
        if ($testExitCode -eq 0 -and $testResult.Passed) { break }
        # A per-process RGL log proves only that the launcher emitted a log; it is not crash evidence.
        # Retry once only when the test itself observed an explicit crash signature or crash-report window.
        if (-not $startupAssessment.ShouldRetry) { break }
    }
    $stageOutput = [ordered]@{ scenario = 'FreshCampaignProgressionWithExplicitCrashOnlyRetry'; attempts = $attempts; finalResult = $finalResult; passed = [bool]($finalResult.Passed -and $attempts[-1].exitCode -eq 0) }
    $stageOutput | ConvertTo-Json -Depth 8
    if (-not $stageOutput.passed) { throw 'Fresh campaign recruitment progression failed after bounded startup recovery.' }
}
