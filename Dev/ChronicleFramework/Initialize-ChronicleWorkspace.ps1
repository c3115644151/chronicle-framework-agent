[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot
)

$ErrorActionPreference = 'Stop'
$gitRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) { throw "Could not resolve the Git repository containing the Harness: $PSScriptRoot" }
$repositoryRoot = [IO.Path]::GetFullPath($gitRoot)
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'Modules\ChronicleFramework\SubModule.xml'))) { throw "The resolved Git root is not a Chronicle Framework source repository: $repositoryRoot" }
$resolvedGameRoot = [IO.Path]::GetFullPath($GameRoot)
$gameExecutable = Join-Path $resolvedGameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
if (-not (Test-Path -LiteralPath $gameExecutable)) { throw "Bannerlord.exe was not found under GameRoot: $resolvedGameRoot" }

$settings = [ordered]@{
    repositoryRoot = $repositoryRoot
    gameRoot = $resolvedGameRoot
}
$settingsPath = Join-Path $PSScriptRoot 'harness.local.json'
$json = $settings | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($settingsPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    SettingsPath = $settingsPath
    RepositoryRoot = $repositoryRoot
    GameRoot = $resolvedGameRoot
} | ConvertTo-Json
