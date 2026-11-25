#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Agent-SaveMetadata.ps1')

$tempRoot = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($tempRoot) -or -not (Test-Path -LiteralPath $tempRoot -PathType Container)) {
    throw 'Save metadata unit test requires the current Harness temp directory.'
}
$fixturePrefix = 'save-module-metadata-' + [Guid]::NewGuid().ToString('N')
$validPath = Join-Path $tempRoot "$fixturePrefix-valid.sav"
$invalidPath = Join-Path $tempRoot "$fixturePrefix-invalid.sav"
$expectedModules = @('Bannerlord.Harmony','Native','SandBoxCore','ChronicleFramework')

try {
    $header = [ordered]@{ List = [ordered]@{ Modules = ($expectedModules -join ';') } } | ConvertTo-Json -Depth 4 -Compress
    $headerBytes = [Text.Encoding]::UTF8.GetBytes($header)
    $stream = [IO.File]::Open($validPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $lengthBytes = [BitConverter]::GetBytes([int]$headerBytes.Length)
        $stream.Write($lengthBytes, 0, $lengthBytes.Length)
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        $payload = [byte[]](0x01, 0x02, 0x03)
        $stream.Write($payload, 0, $payload.Length)
    }
    finally { $stream.Dispose() }

    $actualModules = @(Get-AgentSaveModuleIds -SavePath $validPath)
    if (($actualModules -join '|') -ne ($expectedModules -join '|')) { throw 'Save module parser did not preserve module order and ids.' }

    [IO.File]::WriteAllBytes($invalidPath, [byte[]](0x64,0x00,0x00,0x00,0x7B))
    $invalidRejected = $false
    try { Get-AgentSaveModuleIds -SavePath $invalidPath | Out-Null }
    catch { $invalidRejected = $true }
    if (-not $invalidRejected) { throw 'Save module parser did not reject a truncated metadata header.' }

    [pscustomobject]@{ Passed = $true; OrderedModuleIdsPreserved = $true; TruncatedHeaderRejected = $true }
}
finally {
    Remove-Item -LiteralPath $validPath,$invalidPath -Force -ErrorAction SilentlyContinue
}
