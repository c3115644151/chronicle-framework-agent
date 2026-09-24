[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,
    [string]$GitHubOwner,
    [string]$GitHubRepository,
    [Nullable[int]]$GitHubProjectNumber
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resolvedGameRoot = [IO.Path]::GetFullPath($GameRoot)
$gameExecutable = Join-Path $resolvedGameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
if (-not (Test-Path -LiteralPath $gameExecutable)) { throw "Bannerlord.exe was not found under GameRoot: $resolvedGameRoot" }

$settings = [ordered]@{
    repositoryRoot = $repositoryRoot
    gameRoot = $resolvedGameRoot
    githubOwner = $GitHubOwner
    githubRepository = $GitHubRepository
    githubProjectNumber = if ($GitHubProjectNumber.HasValue) { $GitHubProjectNumber.Value } else { $null }
}
$settingsPath = Join-Path $PSScriptRoot 'harness.local.json'
$json = $settings | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($settingsPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    SettingsPath = $settingsPath
    RepositoryRoot = $repositoryRoot
    GameRoot = $resolvedGameRoot
    GitHubProjectConfigured = ($GitHubOwner -and $GitHubRepository -and $GitHubProjectNumber.HasValue)
} | ConvertTo-Json
