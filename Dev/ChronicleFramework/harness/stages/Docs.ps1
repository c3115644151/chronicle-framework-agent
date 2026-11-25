#Requires -Version 7.0

# Docs stage: the phase table in Run-Harness.ps1 decides when it runs, this file says what it does.
Invoke-Stage -Name 'Docs' -Action {
    & $HarnessPowerShell -NoProfile -File $docsScript
    if ($LASTEXITCODE -ne 0) { throw "Documentation check failed with exit code $LASTEXITCODE." }
    & $HarnessPowerShell -NoProfile -File $contextPackScript
    if ($LASTEXITCODE -ne 0) { throw "Context pack failed with exit code $LASTEXITCODE." }
}
