#Requires -Version 7.0
function Resolve-OpenSpecExecutable {
    $command = Get-Command openspec.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return [IO.Path]::GetFullPath($command.Source) }

    $installDirectory = [Environment]::GetEnvironmentVariable('OPENSPEC_INSTALL_DIR', 'Process')
    if ([string]::IsNullOrWhiteSpace($installDirectory)) { $installDirectory = [Environment]::GetEnvironmentVariable('OPENSPEC_INSTALL_DIR', 'User') }
    $candidates = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($installDirectory)) { $candidates.Add((Join-Path $installDirectory 'openspec.exe')) }
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) { $candidates.Add((Join-Path $localAppData 'Programs\openspec\openspec.exe')) }
    $candidates.Add('D:\ChronicleFramework\Tools\OpenSpec\openspec.exe')
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw 'OpenSpec CLI is required for this Harness workspace. Install the standalone CLI or set OPENSPEC_INSTALL_DIR; no model or game was started.'
}

function Invoke-OpenSpecJsonCommand([string]$ExecutablePath, [string[]]$Arguments) {
    $output = (& $ExecutablePath @Arguments 2>&1 | Out-String)
    $exitCode = if ($LASTEXITCODE -is [int]) { $LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) { throw "OpenSpec command '$($Arguments -join ' ')' failed with exit code ${exitCode}: $output" }
    try { return $output | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "OpenSpec command '$($Arguments -join ' ')' returned invalid JSON: $($_.Exception.Message)" }
}

function Get-OpenSpecWorkspaceSummary {
    [CmdletBinding()]
    param(
        [switch]$Validate,
        [ValidateRange(0,10)][int]$MaximumActiveChanges = 1
    )

    $executable = Resolve-OpenSpecExecutable
    # The CLI resolves the OpenSpec root from the process working directory, so the
    # summary must never depend on where the caller happened to be sitting.
    $openspecRoot = Split-Path -Parent $PSScriptRoot
    $previousLocation = $PWD.ProviderPath
    Push-Location -LiteralPath $openspecRoot
    $previousTelemetry = [Environment]::GetEnvironmentVariable('OPENSPEC_TELEMETRY', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('OPENSPEC_TELEMETRY', '0', 'Process')
        $list = Invoke-OpenSpecJsonCommand $executable @('list', '--json')
        $changes = @($list.changes)
        if ($changes.Count -gt $MaximumActiveChanges) {
            throw "OpenSpec has $($changes.Count) active changes; the Harness allows at most $MaximumActiveChanges to keep project focus singular."
        }

        $currentChange = $null
        if ($changes.Count -eq 1) {
            $change = $changes[0]
            $status = Invoke-OpenSpecJsonCommand $executable @('status', '--change', [string]$change.name, '--json')
            $currentChange = [pscustomobject]@{
                Name = [string]$change.name
                Status = [string]$change.status
                CompletedTasks = [int]$change.completedTasks
                TotalTasks = [int]$change.totalTasks
                Artifacts = @($status.artifacts | ForEach-Object { [pscustomobject]@{ Id = [string]$_.id; Status = [string]$_.status } })
            }
        }

        $validation = $null
        if ($Validate) {
            $validation = Invoke-OpenSpecJsonCommand $executable @('validate', '--all', '--json', '--no-interactive')
            $failed = [int]$validation.summary.totals.failed
            if ($failed -gt 0) { throw "OpenSpec validation reports $failed invalid changes/specs." }
        }

        return [pscustomobject]@{
            Available = $true
            Version = ((& $executable --version 2>&1 | Out-String).Trim())
            Root = [string]$list.root.path
            ActiveChangeCount = $changes.Count
            CurrentChange = $currentChange
            Validation = if ($Validate) { [pscustomobject]@{ Passed = ([int]$validation.summary.totals.failed -eq 0); Total = [int]$validation.summary.totals.items; Failed = [int]$validation.summary.totals.failed } } else { $null }
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('OPENSPEC_TELEMETRY', $previousTelemetry, 'Process')
        Pop-Location
    }
}
