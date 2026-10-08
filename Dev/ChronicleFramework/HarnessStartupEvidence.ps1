function ConvertTo-ChronicleLogTail {
    [CmdletBinding()]
    param([object[]]$Lines = @())

    @($Lines | ForEach-Object { [pscustomobject]@{ text = $_.ToString() } })
}

function Get-ChronicleSteamClientReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$SteamProcessCount,
        [Parameter(Mandatory)][int]$WebHelperProcessCount,
        [Parameter(Mandatory)][double]$WebHelperStableSeconds,
        [ValidateRange(0,60)][double]$RequiredStableSeconds = 5
    )

    $reason = if ($SteamProcessCount -le 0) { 'steam-process-missing' }
        elseif ($WebHelperProcessCount -le 0) { 'steam-webhelper-not-started' }
        elseif ($WebHelperStableSeconds -lt $RequiredStableSeconds) { 'steam-webhelper-not-stable' }
        else { 'ready' }
    [pscustomobject]@{
        Ready = ($reason -eq 'ready')
        Reason = $reason
        SteamProcessCount = $SteamProcessCount
        WebHelperProcessCount = $WebHelperProcessCount
        WebHelperStableSeconds = [Math]::Round($WebHelperStableSeconds,2)
        RequiredStableSeconds = $RequiredStableSeconds
    }
}

function Test-ChronicleSteamClientReadiness {
    $missingSteam = Get-ChronicleSteamClientReadiness -SteamProcessCount 0 -WebHelperProcessCount 0 -WebHelperStableSeconds 0
    $startingClient = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 0 -WebHelperStableSeconds 0
    $warmingHelper = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 1 -WebHelperStableSeconds 4.9
    $readyClient = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 1 -WebHelperStableSeconds 5
    return (-not $missingSteam.Ready -and $missingSteam.Reason -eq 'steam-process-missing' -and
        -not $startingClient.Ready -and $startingClient.Reason -eq 'steam-webhelper-not-started' -and
        -not $warmingHelper.Ready -and $warmingHelper.Reason -eq 'steam-webhelper-not-stable' -and
        $readyClient.Ready -and $readyClient.Reason -eq 'ready')
}

function ConvertTo-ChronicleStartupDialogEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Snapshot)

    $controls = @($Snapshot.Controls | ForEach-Object {
        [ordered]@{
            Name = [string]$_.Name
            ControlType = [string]$_.ControlType
            ClassName = [string]$_.ClassName
            AutomationId = [string]$_.AutomationId
            NativeWindowHandle = [int]$_.NativeWindowHandle
            Patterns = @($_.Patterns | ForEach-Object { [string]$_ })
        }
    })
    return [ordered]@{
        ProcessId = [int]$Snapshot.ProcessId
        WindowTitle = [string]$Snapshot.WindowTitle
        DialogText = [string]$Snapshot.DialogText
        ActionNames = @($Snapshot.ActionNames | ForEach-Object { [string]$_ })
        Controls = $controls
    }
}

function Test-ChronicleStartupDialogEvidenceSerialization {
    $snapshot = [pscustomobject]@{
        ProcessId = 42
        WindowTitle = 'Warning'
        DialogText = 'Unable to initialize Steam API.'
        ActionNames = @((-join @([char]0x786E,[char]0x5B9A)))
        ActionElements = @([pscustomobject]@{ Current = [pscustomobject]@{ Name = 'live UIA proxy must not be serialized' } })
        Controls = @([pscustomobject]@{ Name = (-join @([char]0x786E,[char]0x5B9A)); ControlType = 'ControlType.Pane'; ClassName = 'Button'; AutomationId = '2'; NativeWindowHandle = 99; Patterns = @() })
    }
    $safeEvidence = ConvertTo-ChronicleStartupDialogEvidence -Snapshot $snapshot
    $json = ConvertTo-Json -InputObject $safeEvidence -Depth 8 -Compress
    return ([int]$safeEvidence.ProcessId -eq 42 -and [string]$safeEvidence.DialogText -match 'Steam API' -and
        @($safeEvidence.Controls).Count -eq 1 -and $json -notmatch 'ActionElements|live UIA proxy' -and $json.Length -lt 2048)
}

function Test-ChronicleLogTailNormalization {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $rawLines = @(Get-Content -LiteralPath $Path -Tail 8 -Encoding UTF8)
    $projectedLines = @(ConvertTo-ChronicleLogTail -Lines $rawLines)
    $json = ConvertTo-Json -InputObject ([ordered]@{ rglTail = $projectedLines }) -Depth 8 -Compress
    if ($json.Length -gt 4096) { throw 'Normalized log-tail JSON unexpectedly expanded.' }
    $roundTrip = $json | ConvertFrom-Json
    if (@($roundTrip.rglTail).Count -ne $rawLines.Count) { throw 'Normalized log-tail JSON lost lines.' }
    foreach ($line in $roundTrip.rglTail) {
        $propertyNames = @($line.PSObject.Properties.Name)
        if ($propertyNames.Count -ne 1 -or $propertyNames[0] -ne 'text') { throw 'Normalized log-tail JSON retained provider metadata.' }
    }
    return $true
}

function Get-ChronicleStartupAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Attempt,
        [bool]$GameStarted,
        [bool]$NativeNewCampaignRequested,
        [bool]$CrashDetected,
        [string]$CrashWindowTitle,
        [bool]$SaveDirectoryMetadataUnchanged,
        [bool]$RglLogExists
    )

    $explicitCrash = $CrashDetected -or $CrashWindowTitle -match '(?i)Crash Report|CrashReporter'
    $classification = if ($explicitCrash) { 'explicit-crash' }
        elseif ($GameStarted) { 'game-started' }
        elseif ($NativeNewCampaignRequested) { 'campaign-requested-before-game-start' }
        else { 'pre-game-start-incomplete' }
    [pscustomobject]@{
        Classification = $classification
        ExplicitCrash = [bool]$explicitCrash
        RglLogObserved = $RglLogExists
        ShouldRetry = [bool]($Attempt -eq 1 -and -not $GameStarted -and -not $NativeNewCampaignRequested -and $explicitCrash -and $SaveDirectoryMetadataUnchanged)
    }
}

function Test-ChronicleStartupAssessment {
    $rglOnly = Get-ChronicleStartupAssessment -Attempt 1 -RglLogExists $true
    if ($rglOnly.Classification -ne 'pre-game-start-incomplete' -or $rglOnly.ShouldRetry -or -not $rglOnly.RglLogObserved) { throw 'RGL-log-only startup evidence was misclassified or retried.' }

    $crash = Get-ChronicleStartupAssessment -Attempt 1 -CrashDetected $true -SaveDirectoryMetadataUnchanged $true
    if ($crash.Classification -ne 'explicit-crash' -or -not $crash.ShouldRetry) { throw 'An explicit pre-game crash with unchanged saves must receive exactly one retry.' }

    $campaignStarted = Get-ChronicleStartupAssessment -Attempt 1 -NativeNewCampaignRequested $true -CrashDetected $true -SaveDirectoryMetadataUnchanged $true
    if ($campaignStarted.ShouldRetry) { throw 'A crash after a new campaign request must not be retried as a pre-game startup failure.' }

    $secondAttempt = Get-ChronicleStartupAssessment -Attempt 2 -CrashDetected $true -SaveDirectoryMetadataUnchanged $true
    if ($secondAttempt.ShouldRetry) { throw 'An explicit crash may not trigger more than one retry.' }
    return $true
}

if ($MyInvocation.InvocationName -ne '.') { Test-ChronicleStartupAssessment | Out-Null }
