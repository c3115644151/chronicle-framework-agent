function ConvertTo-ChronicleLogTail {
    [CmdletBinding()]
    param([object[]]$Lines = @())

    @($Lines | ForEach-Object { [pscustomobject]@{ text = $_.ToString() } })
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
