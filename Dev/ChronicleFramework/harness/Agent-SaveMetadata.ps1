#Requires -Version 7.0
function Get-AgentSaveModuleIds {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SavePath)

    if (-not (Test-Path -LiteralPath $SavePath -PathType Leaf)) { throw "Save metadata source does not exist: $SavePath" }
    $stream = [IO.File]::Open($SavePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 8) { throw 'Save file is too short to contain a metadata header.' }
        $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            $headerLength = $reader.ReadInt32()
            if ($headerLength -lt 2 -or $headerLength -gt 1048576 -or $headerLength -gt ($stream.Length - 4)) {
                throw "Save metadata header length is invalid: $headerLength."
            }
            $headerBytes = $reader.ReadBytes($headerLength)
            if ($headerBytes.Length -ne $headerLength) { throw 'Save metadata header is truncated.' }
            $metadata = [Text.Encoding]::UTF8.GetString($headerBytes) | ConvertFrom-Json
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }

    $moduleText = [string]$metadata.List.Modules
    if ([string]::IsNullOrWhiteSpace($moduleText)) { throw 'Save metadata does not contain List.Modules; refusing to guess a module set.' }
    $moduleIds = @($moduleText.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($moduleIds.Count -eq 0 -or @($moduleIds | Sort-Object -Unique).Count -ne $moduleIds.Count) { throw 'Save metadata contains an empty or duplicate module list.' }
    foreach ($moduleId in $moduleIds) {
        if ($moduleId -notmatch '^[A-Za-z0-9._-]+$') { throw "Save metadata contains an invalid module id: '$moduleId'." }
    }
    return $moduleIds
}
