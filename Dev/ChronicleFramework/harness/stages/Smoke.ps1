#Requires -Version 7.0

# Smoke stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Smoke' -Action {
    $priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
    $env:CHRONICLE_HARNESS_MODE = 'smoke'
    try {
        $smokeStdout = Join-Path $harnessTempDirectory 'SmokeWorker.stdout.log'
        $smokeStderr = Join-Path $harnessTempDirectory 'SmokeWorker.stderr.log'
        $smokeWorker = Start-Process -FilePath $HarnessPowerShell -ArgumentList @('-NoProfile','-File',('"' + $smokeScript + '"'),'-TimeoutSeconds',$effectiveSmokeTimeoutSeconds,'-StabilitySeconds',$SmokeStabilitySeconds) -WindowStyle Hidden -RedirectStandardOutput $smokeStdout -RedirectStandardError $smokeStderr -PassThru
        try {
            if (-not $smokeWorker.WaitForExit(($effectiveSmokeTimeoutSeconds + $SmokeStabilitySeconds + 30) * 1000)) {
                $ownedGameExe = [IO.Path]::GetFullPath((Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'))
                $ownedChildren = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($smokeWorker.Id)")
                foreach ($ownedChild in $ownedChildren) {
                    if ($ownedChild.ExecutablePath -and [IO.Path]::GetFullPath($ownedChild.ExecutablePath) -eq $ownedGameExe) {
                        Stop-Process -Id $ownedChild.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                }
                $smokeWorker.Kill()
                $smokeWorker.WaitForExit()
                throw "Smoke worker exceeded its startup/stability/receipt deadline; worker logs and receipt-stage markers are retained in $harnessTempDirectory."
            }
            # A redirected worker that runs for minutes can exit without publishing an exit code on the Process object, so the receipt gate below decides the stage; the exit code is only an additional failure signal.
            $smokeWorker.WaitForExit()
            try { $smokeExitCode = $smokeWorker.ExitCode } catch { $smokeExitCode = $null }
        }
        finally { $smokeWorker.Dispose() }
        $smokeOutput = (Get-Content -LiteralPath $smokeStdout -Raw) + (Get-Content -LiteralPath $smokeStderr -Raw)
        if ($null -ne $smokeExitCode -and $smokeExitCode -ne 0) { throw "Smoke test failed with exit code $smokeExitCode. Evidence: $smokeOutput" }
        $smokeReceipt = Get-Content -LiteralPath (Join-Path $harnessTempDirectory 'SmokeResult.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($flagName in @('FinishedAll','AssemblyLoaded','CrashDetected','McmSettingsRegistered','StableAfterFinishedAll','ProcessExitedUnexpectedly')) {
            if ($smokeReceipt.$flagName -isnot [bool]) { throw "Smoke receipt field '$flagName' must be a Boolean; collection/string truthiness is not verification." }
        }
        if ($smokeReceipt.Passed -isnot [bool]) { throw "Smoke receipt field 'Passed' must be a Boolean; the worker has to serialize its own gate verdict." }
        if (-not $smokeReceipt.Passed) { throw "Smoke worker reported its gate failed: $(@($smokeReceipt.GateFailures) -join ', '). Evidence: $smokeOutput" }
        if ($null -eq $smokeExitCode) { $smokeOutput += "`nSmoke worker exit code was unavailable; the stage verdict came from the worker receipt (Passed=true)." }
    }
    finally {
        if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    }
    $smokeOutput
}
