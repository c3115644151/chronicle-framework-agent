function ConvertTo-ChronicleReceiptValue {
    param([AllowNull()][object]$Value, [int]$Depth = 0)
    if ($Depth -gt 12) { throw 'Receipt data exceeds its supported nesting depth.' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return [string]::new($Value.ToCharArray()) }
    if ($Value.GetType().IsPrimitive -or $Value -is [decimal]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $plain = [ordered]@{}
        foreach ($key in $Value.Keys) { $plain[[string]$key] = ConvertTo-ChronicleReceiptValue -Value $Value[$key] -Depth ($Depth + 1) }
        return $plain
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value | ForEach-Object { ConvertTo-ChronicleReceiptValue -Value $_ -Depth ($Depth + 1) })
        return ,$items
    }
    if ($Value -is [pscustomobject]) {
        $plain = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -eq 'NoteProperty') { $plain[$property.Name] = ConvertTo-ChronicleReceiptValue -Value $property.Value -Depth ($Depth + 1) }
        }
        return $plain
    }
    throw "Unsupported live receipt value type: $($Value.GetType().FullName)"
}

function ConvertTo-ChronicleReceiptJson {
    param([Parameter(Mandatory)][object]$Value)
    $plain = ConvertTo-ChronicleReceiptValue -Value $Value
    if ($PSVersionTable.PSVersion.Major -le 5) {
        Add-Type -AssemblyName System.Web.Extensions
        $serializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
        $serializer.MaxJsonLength = 1048576
        $serializer.RecursionLimit = 16
        return $serializer.Serialize($plain)
    }
    return ConvertTo-Json -InputObject $plain -Depth 16 -Compress
}

function ConvertTo-ChronicleLogTail {
    [CmdletBinding()]
    param([object[]]$Lines = @())

    @($Lines | ForEach-Object { [pscustomobject]@{ text = $_.ToString() } })
}

function Get-ChronicleBannerlordAutoSavePaths {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace($documents)) { throw 'Windows Documents directory could not be resolved for Bannerlord auto-save isolation.' }
    $configDirectory = Join-Path (Join-Path $documents 'Mount and Blade II Bannerlord') 'Configs'
    [pscustomobject]@{
        ConfigPath = Join-Path $configDirectory 'BannerlordConfig.txt'
        BackupPath = Join-Path $configDirectory 'BannerlordConfig.chronicle-autosave-backup.json'
    }
}

function Get-ChronicleBannerlordAutoSaveInterval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { throw "Bannerlord configuration file not found: $LiteralPath" }
    $content = [IO.File]::ReadAllText($LiteralPath)
    $matches = [regex]::Matches($content, '(?m)^AutoSaveInterval=(-?\d+)\r?$')
    if ($matches.Count -ne 1) { throw 'BannerlordConfig.txt must contain exactly one AutoSaveInterval setting; refusing to guess.' }
    [int]$value = 0
    if (-not [int]::TryParse($matches[0].Groups[1].Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { throw 'BannerlordConfig.txt AutoSaveInterval is not a valid integer.' }
    $value
}

function Set-ChronicleBannerlordAutoSaveInterval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath, [Parameter(Mandatory)][int]$Value)
    $content = [IO.File]::ReadAllText($LiteralPath)
    $pattern = '(?m)^AutoSaveInterval=(-?\d+)(\r?)$'
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1) { throw 'BannerlordConfig.txt must contain exactly one AutoSaveInterval setting; refusing to change configuration.' }
    $regex = [regex]::new($pattern)
    $updated = $regex.Replace($content, [Text.RegularExpressions.MatchEvaluator]{ param($match) "AutoSaveInterval=$Value$($match.Groups[2].Value)" }, 1)
    [IO.File]::WriteAllText($LiteralPath, $updated, [Text.UTF8Encoding]::new($true))
    $actual = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $LiteralPath
    if ($actual -ne $Value) { throw "Bannerlord AutoSaveInterval did not accept the requested Harness value ($Value)." }
}

function Restore-ChronicleHarnessAutoSaveSetting {
    [CmdletBinding()]
    param()
    $paths = Get-ChronicleBannerlordAutoSavePaths
    if (-not (Test-Path -LiteralPath $paths.BackupPath -PathType Leaf)) { return [pscustomobject]@{ Status = 'not-needed'; Restored = $true } }
    $runningGames = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($runningGames.Count -gt 0) { return [pscustomobject]@{ Status = 'deferred-game-running'; Restored = $false; ProcessIds = @($runningGames.Id) } }

    $backup = Get-Content -LiteralPath $paths.BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$backup.schemaVersion -ne 1 -or [IO.Path]::GetFullPath([string]$backup.configPath) -ne [IO.Path]::GetFullPath($paths.ConfigPath)) {
        return [pscustomobject]@{ Status = 'backup-invalid'; Restored = $false }
    }
    $current = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $paths.ConfigPath
    $original = [int]$backup.originalAutoSaveInterval
    if ($current -eq $original) {
        Remove-Item -LiteralPath $paths.BackupPath -Force
        return [pscustomobject]@{ Status = 'already-restored'; Restored = $true; AutoSaveInterval = $current }
    }
    if ($current -ne -1) {
        return [pscustomobject]@{ Status = 'configuration-conflict'; Restored = $false; CurrentAutoSaveInterval = $current; ExpectedHarnessValue = -1 }
    }
    Set-ChronicleBannerlordAutoSaveInterval -LiteralPath $paths.ConfigPath -Value $original
    $restored = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $paths.ConfigPath
    if ($restored -ne $original) { throw 'Restoring the original Bannerlord AutoSaveInterval did not verify.' }
    Remove-Item -LiteralPath $paths.BackupPath -Force
    [pscustomobject]@{ Status = 'restored'; Restored = $true; AutoSaveInterval = $restored }
}

function Disable-ChronicleHarnessAutoSave {
    [CmdletBinding()]
    param()
    $paths = Get-ChronicleBannerlordAutoSavePaths
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Refusing to change Bannerlord auto-save settings while a game process is running.' }
    if (Test-Path -LiteralPath $paths.BackupPath -PathType Leaf) {
        $recovery = Restore-ChronicleHarnessAutoSaveSetting
        if (-not $recovery.Restored) { throw "An unresolved Bannerlord auto-save backup prevents a fresh test ($($recovery.Status)); no game was started." }
    }
    $original = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $paths.ConfigPath
    if ($original -eq -1) { return [pscustomobject]@{ Status = 'already-disabled'; OriginalAutoSaveInterval = -1; SettingDuringTest = -1; BackupPath = $null } }
    $backup = [ordered]@{
        schemaVersion = 1
        configPath = [IO.Path]::GetFullPath($paths.ConfigPath)
        originalAutoSaveInterval = $original
        createdUtc = [DateTime]::UtcNow.ToString('O')
        recoveryRule = 'Restore only when no Bannerlord process is running and current AutoSaveInterval is still exactly -1.'
    }
    [IO.File]::WriteAllText($paths.BackupPath, ($backup | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($true))
    try { Set-ChronicleBannerlordAutoSaveInterval -LiteralPath $paths.ConfigPath -Value -1 }
    catch {
        try { [void](Restore-ChronicleHarnessAutoSaveSetting) } catch { }
        throw
    }
    [pscustomobject]@{ Status = 'disabled'; OriginalAutoSaveInterval = $original; SettingDuringTest = -1; BackupPath = $paths.BackupPath }
}

function Get-ChronicleEngineConfigPath {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace($documents)) { throw 'Windows Documents directory could not be resolved for Bannerlord sound isolation.' }
    Join-Path (Join-Path $documents 'Mount and Blade II Bannerlord\Configs') 'engine_config.txt'
}

function Get-ChronicleBannerlordSoundDisabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { throw 'Bannerlord engine_config.txt was not found; sound will remain unchanged.' }
    $content = [IO.File]::ReadAllText($LiteralPath)
    $matches = [regex]::Matches($content, '(?m)^disable_sound\s*=\s*(\d+)\s*\r?$')
    if ($matches.Count -ne 1) { throw 'engine_config.txt must contain exactly one disable_sound setting; refusing to guess.' }
    $value = 0
    if (-not [int]::TryParse($matches[0].Groups[1].Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -notin @(0,1)) {
        throw 'engine_config.txt disable_sound must be either 0 or 1.'
    }
    return $value
}

function Set-ChronicleBannerlordSoundDisabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath, [Parameter(Mandatory)][ValidateSet(0,1)][int]$Value)
    $content = [IO.File]::ReadAllText($LiteralPath)
    $pattern = '(?m)^(disable_sound\s*=\s*)(\d+)(\s*\r?)$'
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1) { throw 'engine_config.txt must contain exactly one disable_sound setting; refusing to change configuration.' }
    $bytes = [IO.File]::ReadAllBytes($LiteralPath)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $encoding = [Text.UTF8Encoding]::new($hasUtf8Bom)
    $updated = ([regex]::new($pattern)).Replace($content, [Text.RegularExpressions.MatchEvaluator]{ param($match) "$($match.Groups[1].Value)$Value$($match.Groups[3].Value)" }, 1)
    [IO.File]::WriteAllText($LiteralPath, $updated, $encoding)
    $actual = Get-ChronicleBannerlordSoundDisabled -LiteralPath $LiteralPath
    if ($actual -ne $Value) { throw "Bannerlord disable_sound did not accept the requested Harness value ($Value)." }
}

function Restore-ChronicleHarnessGameSound {
    [CmdletBinding()]
    param()
    $configPath = Get-ChronicleEngineConfigPath
    $backupPath = "$configPath.chronicle-sound-backup.json"
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { return [pscustomobject]@{ Status = 'not-needed'; Restored = $true } }
    $runningGames = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($runningGames.Count -gt 0) { return [pscustomobject]@{ Status = 'deferred-game-running'; Restored = $false; ProcessIds = @($runningGames.Id) } }
    $backup = Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$backup.schemaVersion -ne 1 -or [IO.Path]::GetFullPath([string]$backup.configPath) -ne [IO.Path]::GetFullPath($configPath)) {
        return [pscustomobject]@{ Status = 'backup-invalid'; Restored = $false }
    }
    $current = Get-ChronicleBannerlordSoundDisabled -LiteralPath $configPath
    $original = [int]$backup.originalDisableSound
    if ($current -eq $original) {
        Remove-Item -LiteralPath $backupPath -Force
        return [pscustomobject]@{ Status = 'already-restored'; Restored = $true; DisableSound = $current }
    }
    if ($current -ne 1) { return [pscustomobject]@{ Status = 'configuration-conflict'; Restored = $false; CurrentDisableSound = $current; ExpectedHarnessValue = 1 } }
    Set-ChronicleBannerlordSoundDisabled -LiteralPath $configPath -Value $original
    $restored = Get-ChronicleBannerlordSoundDisabled -LiteralPath $configPath
    if ($restored -ne $original) { throw 'Restoring the original Bannerlord disable_sound setting did not verify.' }
    Remove-Item -LiteralPath $backupPath -Force
    [pscustomobject]@{ Status = 'restored'; Restored = $true; DisableSound = $restored }
}

function Disable-ChronicleHarnessGameSound {
    [CmdletBinding()]
    param()
    $configPath = Get-ChronicleEngineConfigPath
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Refusing to change game sound configuration while Bannerlord is running.' }
    $backupPath = "$configPath.chronicle-sound-backup.json"
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        $recovery = Restore-ChronicleHarnessGameSound
        if (-not $recovery.Restored) { throw "An unresolved Bannerlord sound backup prevents a fresh test ($($recovery.Status)); no game was started." }
    }
    $original = Get-ChronicleBannerlordSoundDisabled -LiteralPath $configPath
    if ($original -eq 1) { return [pscustomobject]@{ Status = 'already-disabled'; OriginalDisableSound = 1; DisableSoundDuringTest = 1; BackupPath = $null } }
    $backup = [ordered]@{
        schemaVersion = 1
        configPath = [IO.Path]::GetFullPath($configPath)
        originalDisableSound = $original
        createdUtc = [DateTime]::UtcNow.ToString('O')
        recoveryRule = 'Restore only when no Bannerlord process is running and disable_sound is still exactly 1.'
    }
    [IO.File]::WriteAllText($backupPath, ($backup | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($true))
    try { Set-ChronicleBannerlordSoundDisabled -LiteralPath $configPath -Value 1 }
    catch {
        try { [void](Restore-ChronicleHarnessGameSound) } catch { }
        throw
    }
    [pscustomobject]@{ Status = 'disabled'; OriginalDisableSound = $original; DisableSoundDuringTest = 1; BackupPath = $backupPath }
}

function Get-ChronicleSteamClientReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$SteamProcessCount,
        [Parameter(Mandatory)][int]$WebHelperProcessCount,
        [Parameter(Mandatory)][double]$WebHelperStableSeconds,
        [bool]$SteamLoginReady = $false,
        [ValidateRange(0,60)][double]$RequiredStableSeconds = 5
    )

    $reason = if ($SteamProcessCount -le 0) { 'steam-process-missing' }
        elseif ($WebHelperProcessCount -le 0) { 'steam-webhelper-not-started' }
        elseif ($WebHelperStableSeconds -lt $RequiredStableSeconds) { 'steam-webhelper-not-stable' }
        elseif (-not $SteamLoginReady) { 'steam-user-not-logged-on' }
        else { 'ready' }
    [pscustomobject]@{
        Ready = ($reason -eq 'ready')
        Reason = $reason
        SteamProcessCount = $SteamProcessCount
        WebHelperProcessCount = $WebHelperProcessCount
        WebHelperStableSeconds = [Math]::Round($WebHelperStableSeconds,2)
        SteamLoginReady = $SteamLoginReady
        RequiredStableSeconds = $RequiredStableSeconds
    }
}

function Get-ChronicleSteamLoginState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [datetime]$RequireEventAfterUtc = [datetime]::MinValue
    )

    $latestState = $null
    foreach ($line in $Lines) {
        if ($line -notmatch '^\[(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]\s+\[(?<state>Logged On|Logged Off),') { continue }
        $localTimestamp = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Matches.timestamp, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeLocal, [ref]$localTimestamp)) { continue }
        $latestState = [pscustomobject]@{
            LoggedOn = ($Matches.state -eq 'Logged On')
            EventUtc = $localTimestamp.ToUniversalTime()
        }
    }

    if ($null -eq $latestState) { return [pscustomobject]@{ Ready = $false; Reason = 'steam-login-state-unavailable'; EventUtc = $null } }
    if (-not $latestState.LoggedOn) { return [pscustomobject]@{ Ready = $false; Reason = 'steam-user-not-logged-on'; EventUtc = $latestState.EventUtc.ToString('O') } }
    if ($RequireEventAfterUtc -ne [datetime]::MinValue -and $latestState.EventUtc -lt $RequireEventAfterUtc) {
        return [pscustomobject]@{ Ready = $false; Reason = 'steam-login-event-predates-current-client-start'; EventUtc = $latestState.EventUtc.ToString('O') }
    }
    return [pscustomobject]@{ Ready = $true; Reason = 'steam-user-logged-on'; EventUtc = $latestState.EventUtc.ToString('O') }
}

function Ensure-ChronicleSteamClientReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SteamRoot,
        [ValidateRange(1,180)][int]$TimeoutSeconds = 45,
        [ValidateRange(0,60)][double]$RequiredStableSeconds = 5
    )

    $resolvedSteamRoot = [IO.Path]::GetFullPath($SteamRoot)
    $steamExe = Join-Path $resolvedSteamRoot 'steam.exe'
    if (-not (Test-Path -LiteralPath $steamExe -PathType Leaf)) {
        throw "Steam client is not running and the expected Steam executable is not present at '$steamExe'."
    }

    $startedByHarness = $false
    $steamStartedUtc = [datetime]::MinValue
    if (@(Get-Process -Name 'steam' -ErrorAction SilentlyContinue).Count -eq 0) {
        $steamStartedUtc = [DateTime]::UtcNow
        Start-Process -FilePath $steamExe -ArgumentList '-silent' -WorkingDirectory $resolvedSteamRoot -WindowStyle Hidden | Out-Null
        $startedByHarness = $true
    }

    $connectionLogPath = Join-Path $resolvedSteamRoot 'logs\connection_log.txt'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $steamProcesses = @()
    $webHelperProcesses = @()
    $webHelperSignature = ''
    $webHelperStableSinceUtc = $null
    $readiness = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $steamProcesses = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
        $webHelperProcesses = @(Get-Process -Name 'steamwebhelper' -ErrorAction SilentlyContinue)
        $currentWebHelperSignature = (@($webHelperProcesses | ForEach-Object { [int]$_.Id } | Sort-Object) -join ',')
        if ([string]::IsNullOrWhiteSpace($currentWebHelperSignature)) {
            $webHelperSignature = ''
            $webHelperStableSinceUtc = $null
        }
        elseif ($currentWebHelperSignature -cne $webHelperSignature) {
            $webHelperSignature = $currentWebHelperSignature
            $webHelperStableSinceUtc = [DateTime]::UtcNow
        }
        $stableSeconds = if ($webHelperStableSinceUtc) { ([DateTime]::UtcNow - $webHelperStableSinceUtc).TotalSeconds } else { 0 }
        $connectionLines = if (Test-Path -LiteralPath $connectionLogPath -PathType Leaf) { @(Get-Content -LiteralPath $connectionLogPath -Tail 512 -Encoding UTF8) } else { @() }
        $loginState = Get-ChronicleSteamLoginState -Lines $connectionLines -RequireEventAfterUtc $steamStartedUtc
        $readiness = Get-ChronicleSteamClientReadiness -SteamProcessCount $steamProcesses.Count -WebHelperProcessCount $webHelperProcesses.Count -WebHelperStableSeconds $stableSeconds -SteamLoginReady $loginState.Ready -RequiredStableSeconds $RequiredStableSeconds
        if ($readiness.Ready) {
            return [ordered]@{
                available = $true
                startedByHarness = $startedByHarness
                processIds = @($steamProcesses | ForEach-Object { [int]$_.Id })
                webHelperProcessIds = @($webHelperProcesses | ForEach-Object { [int]$_.Id })
                readyUtc = [DateTime]::UtcNow.ToString('O')
                loginState = $loginState
                readiness = $readiness
            }
        }
        Start-Sleep -Milliseconds 500
    }

    $reason = if ($readiness) { [string]$readiness.Reason } else { 'no-readiness-sample' }
    throw "Steam client did not reach stable API/login readiness within $TimeoutSeconds seconds (reason='$reason', steamProcesses=$($steamProcesses.Count), webHelperProcesses=$($webHelperProcesses.Count), loginReason='$($loginState.Reason)'). Bannerlord was not launched."
}

function Start-ChronicleSteamGame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateSet('Normal','Hidden','Minimized','Maximized')][string]$WindowStyle = 'Minimized'
    )

    $resolvedWorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    $appIdPath = Join-Path $resolvedWorkingDirectory 'steam_appid.txt'
    if (-not (Test-Path -LiteralPath $appIdPath -PathType Leaf)) {
        throw 'Bannerlord steam_appid.txt is missing from the launch directory; refusing a direct launch that cannot identify the Steam App ID.'
    }
    $appId = (Get-Content -LiteralPath $appIdPath -Raw).Trim()
    if ($appId -ne '261550') {
        throw "Bannerlord steam_appid.txt must contain App ID 261550; found '$appId'."
    }

    # Directly launching the installed executable does not inherit Steam's app
    # identity. Bannerlord's Steamworks initialization fails without these vars
    # even when the Steam client and steam_appid.txt are present. Scope them to
    # this child process only; do not change the caller's persistent environment.
    $priorSteamAppId = [Environment]::GetEnvironmentVariable('SteamAppId', 'Process')
    $priorSteamGameId = [Environment]::GetEnvironmentVariable('SteamGameId', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('SteamAppId', $appId, 'Process')
        [Environment]::SetEnvironmentVariable('SteamGameId', $appId, 'Process')
        return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $resolvedWorkingDirectory -WindowStyle $WindowStyle -PassThru
    }
    finally {
        [Environment]::SetEnvironmentVariable('SteamAppId', $priorSteamAppId, 'Process')
        [Environment]::SetEnvironmentVariable('SteamGameId', $priorSteamGameId, 'Process')
    }
}

function Test-ChronicleSteamClientReadiness {
    $missingSteam = Get-ChronicleSteamClientReadiness -SteamProcessCount 0 -WebHelperProcessCount 0 -WebHelperStableSeconds 0
    $startingClient = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 0 -WebHelperStableSeconds 0
    $warmingHelper = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 1 -WebHelperStableSeconds 4.9
    $stableButLoggedOut = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 1 -WebHelperStableSeconds 8 -SteamLoginReady $false
    $readyClient = Get-ChronicleSteamClientReadiness -SteamProcessCount 1 -WebHelperProcessCount 1 -WebHelperStableSeconds 5 -SteamLoginReady $true
    $requireAfterUtc = [datetime]::SpecifyKind([datetime]::ParseExact('2026-11-03 05:19:42', 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture), [DateTimeKind]::Local).ToUniversalTime()
    $loggedOnLines = @('[2026-11-03 05:19:44] [Connecting, 4, 7] Logging on', '[2026-11-03 05:19:47] [Logged On, 4, 7] processing complete')
    $loggedOffLines = @('[2026-11-03 05:19:44] [Logged On, 4, 7] processing complete', '[2026-11-03 05:19:48] [Logged Off, 4, 0] connection closed')
    $loggedOn = Get-ChronicleSteamLoginState -Lines $loggedOnLines -RequireEventAfterUtc $requireAfterUtc
    $predatesStart = Get-ChronicleSteamLoginState -Lines $loggedOnLines -RequireEventAfterUtc ($requireAfterUtc.AddMinutes(1))
    $loggedOff = Get-ChronicleSteamLoginState -Lines $loggedOffLines
    return (-not $missingSteam.Ready -and $missingSteam.Reason -eq 'steam-process-missing' -and
        -not $startingClient.Ready -and $startingClient.Reason -eq 'steam-webhelper-not-started' -and
        -not $warmingHelper.Ready -and $warmingHelper.Reason -eq 'steam-webhelper-not-stable' -and
        -not $stableButLoggedOut.Ready -and $stableButLoggedOut.Reason -eq 'steam-user-not-logged-on' -and
        $loggedOn.Ready -and $loggedOn.Reason -eq 'steam-user-logged-on' -and
        -not $predatesStart.Ready -and $predatesStart.Reason -eq 'steam-login-event-predates-current-client-start' -and
        -not $loggedOff.Ready -and $loggedOff.Reason -eq 'steam-user-not-logged-on' -and
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
    $json = ConvertTo-ChronicleReceiptJson -Value $safeEvidence
    return ([int]$safeEvidence.ProcessId -eq 42 -and [string]$safeEvidence.DialogText -match 'Steam API' -and
        @($safeEvidence.Controls).Count -eq 1 -and $json -notmatch 'ActionElements|live UIA proxy' -and $json.Length -lt 2048)
}

function Test-ChronicleReceiptSerialization {
    $annotated = 'plain text' | Add-Member -NotePropertyName UnrelatedMetadata -NotePropertyValue ([pscustomobject]@{ nested = 'must not enter receipt' }) -PassThru
    $receipt = [ordered]@{ flag = $true; count = 0; nullable = $null; empty = @(); text = $annotated; nested = @([pscustomobject]@{ name = 'OK'; patterns = @('InvokePattern') }) }
    $json = ConvertTo-ChronicleReceiptJson -Value $receipt
    $back = $json | ConvertFrom-Json
    return ($back.flag -eq $true -and $back.count -eq 0 -and $null -eq $back.nullable -and
        @($back.empty).Count -eq 0 -and $back.text -eq 'plain text' -and
        $back.nested[0].name -eq 'OK' -and $back.nested[0].patterns[0] -eq 'InvokePattern' -and
        $json -notmatch 'UnrelatedMetadata|must not enter receipt')
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
