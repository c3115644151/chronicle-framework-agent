$script:AuditedHarnessDiagnosticSource = 'SubModule.cs'
$script:AuditedHarnessDiagnosticSha256 = '3b3a49f1860603f8aedddf476ffa03de8916a1188aab9be421a7ea4307947a76'

function Get-ChronicleCanonicalTextSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $canonicalContent = [regex]::Replace($Content, "`r`n|`r|`n", "`n")
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($canonicalContent)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-ChronicleCanonicalFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)

    Get-ChronicleCanonicalTextSha256 -Content ([IO.File]::ReadAllText($LiteralPath))
}

function Get-ChronicleResearchReadiness {
    [CmdletBinding()]
    param(
        [bool]$ResearchReady,
        [bool]$ImplementationReady,
        [string[]]$ChangedFeatureSources = @(),
        [string]$AuditedHarnessDiagnosticSha256
    )

    $changed = @($ChangedFeatureSources | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($changed.Count -eq 0) {
        return [pscustomobject]@{ Allowed = $true; ChangedSources = @(); Reason = 'no changed game C# source' }
    }
    if ($ResearchReady -and $ImplementationReady) {
        return [pscustomobject]@{ Allowed = $true; ChangedSources = $changed; Reason = 'readiness evidence is marked READY' }
    }
    if ($changed.Count -eq 1 -and $changed[0] -eq $script:AuditedHarnessDiagnosticSource -and
        $AuditedHarnessDiagnosticSha256 -eq $script:AuditedHarnessDiagnosticSha256) {
        return [pscustomobject]@{ Allowed = $true; ChangedSources = $changed; Reason = 'exactly hashed Harness-only change; vanilla mechanics unchanged' }
    }
    [pscustomobject]@{
        Allowed = $false
        ChangedSources = $changed
        Reason = 'ResearchReadinessGate blocked C# implementation/build: ' + ($changed -join ', ') + '. Complete the behavior universe, dated sources/applicability, unknowns, reusable capability and repeatable acceptance evidence before setting both MAINLINE gates READY.'
    }
}

function Test-ChronicleResearchReadiness {
    $lfHash = Get-ChronicleCanonicalTextSha256 -Content "line one`nline two`n"
    $crlfHash = Get-ChronicleCanonicalTextSha256 -Content "line one`r`nline two`r`n"
    if ($lfHash -ne $crlfHash) { throw 'Canonical source hashing must treat LF and CRLF as the same reviewed content.' }

    $unchangedBlocked = Get-ChronicleResearchReadiness -ResearchReady:$false -ImplementationReady:$false
    if (-not $unchangedBlocked.Allowed) { throw 'Research gate must permit builds/tests when no game C# source changed.' }

    $changedBlocked = Get-ChronicleResearchReadiness -ResearchReady:$false -ImplementationReady:$false -ChangedFeatureSources @('AgentProtocol.cs')
    if ($changedBlocked.Allowed -or $changedBlocked.Reason -notmatch 'ResearchReadinessGate blocked') { throw 'Changed feature code must be blocked while research/implementation readiness is incomplete.' }

    $changedReady = Get-ChronicleResearchReadiness -ResearchReady:$true -ImplementationReady:$true -ChangedFeatureSources @('AgentProtocol.cs')
    if (-not $changedReady.Allowed) { throw 'Feature code must be buildable after both readiness gates are complete.' }

    $mismatchedReady = Get-ChronicleResearchReadiness -ResearchReady:$true -ImplementationReady:$false -ChangedFeatureSources @('AgentProtocol.cs')
    if ($mismatchedReady.Allowed) { throw 'Both research and implementation gates must be READY.' }

    $diagnosticCleanup = Get-ChronicleResearchReadiness -ResearchReady:$false -ImplementationReady:$false -ChangedFeatureSources @($script:AuditedHarnessDiagnosticSource) -AuditedHarnessDiagnosticSha256 $script:AuditedHarnessDiagnosticSha256
    if (-not $diagnosticCleanup.Allowed) { throw 'The exact audited Harness-only change should remain buildable while gameplay research is blocked.' }

    $modifiedDiagnostic = Get-ChronicleResearchReadiness -ResearchReady:$false -ImplementationReady:$false -ChangedFeatureSources @($script:AuditedHarnessDiagnosticSource) -AuditedHarnessDiagnosticSha256 'not-the-approved-hash'
    if ($modifiedDiagnostic.Allowed) { throw 'Any further SubModule.cs change must be blocked unless re-audited.' }
    return $true
}
