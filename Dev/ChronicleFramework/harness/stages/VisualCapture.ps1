#Requires -Version 7.0

# VisualCapture stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'VisualCapture' -Action {
    & $HarnessPowerShell -NoProfile -File $visualCaptureScript
    if ($LASTEXITCODE -ne 0) { throw "Window-only visual capture failed with exit code $LASTEXITCODE." }
}
