#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(640, 7680)][int]$Width = 1600,
    [ValidateRange(360, 4320)][int]$Height = 900,
    [ValidateRange(30, 240)][int]$FrameRate = 60
)

# Harness capture runs force a small fixed window and restore the previous engine_config when they exit normally.
# A forced stop leaves that capture layout behind; this repairs the player-facing display settings on demand.
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Bannerlord engine_config.txt was not found: $configPath" }
$text = Get-Content -LiteralPath $configPath -Raw
$text = $text -replace '(?m)^display_mode\s*=.*$', 'display_mode = 0'
$text = $text -replace '(?m)^display_width\s*=.*$', ("display_width = " + $Width)
$text = $text -replace '(?m)^display_height\s*=.*$', ("display_height = " + $Height)
$text = $text -replace '(?m)^max_framerate\s*=.*$', ("max_framerate = " + $FrameRate)
Set-Content -LiteralPath $configPath -Value $text -NoNewline
[ordered]@{
    ConfigPath = $configPath
    DisplayMode = 0
    Width = $Width
    Height = $Height
    MaxFrameRate = $FrameRate
    Applied = $true
} | ConvertTo-Json
