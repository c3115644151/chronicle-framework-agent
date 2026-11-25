[CmdletBinding()]
param(
    [ValidateSet('Lifecycle', 'Events', 'Search')]
    [string]$Scope = 'Lifecycle'
)

$ErrorActionPreference = 'Stop'
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$binDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$probeProject = Join-Path $PSScriptRoot 'ApiProbe.csproj'

switch ($Scope) {
    'Lifecycle' {
        dotnet run --project $probeProject -- "$binDirectory\TaleWorlds.MountAndBlade.dll" 'TaleWorlds.MountAndBlade.MBSubModuleBase' 'OnGameStart'
        dotnet run --project $probeProject -- "$binDirectory\TaleWorlds.CampaignSystem.dll" 'TaleWorlds.CampaignSystem.CampaignBehaviorBase'
        dotnet run --project $probeProject -- "$binDirectory\TaleWorlds.CampaignSystem.dll" 'TaleWorlds.CampaignSystem.CampaignGameStarter' 'AddBehavior'
    }
    'Events' {
        foreach ($eventName in @('DailyTickEvent', 'WarDeclared', 'OnSettlementOwnerChangedEvent', 'HeroKilledEvent', 'OnNewGameCreatedEvent', 'OnGameLoadedEvent')) {
            dotnet run --project $probeProject -- "$binDirectory\TaleWorlds.CampaignSystem.dll" 'TaleWorlds.CampaignSystem.CampaignEvents' $eventName
        }
    }
    'Search' {
        dotnet run --project $probeProject -- --search "$binDirectory\TaleWorlds.MountAndBlade.dll" 'LoadGame'
        dotnet run --project $probeProject -- --search "$binDirectory\TaleWorlds.CampaignSystem.dll" 'LoadGame'
        dotnet run --project $probeProject -- --search "$binDirectory\TaleWorlds.MountAndBlade.Launcher.Library.dll" 'LoadGame'
    }
}
