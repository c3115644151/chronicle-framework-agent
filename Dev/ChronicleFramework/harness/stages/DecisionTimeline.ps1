#Requires -Version 7.0

# DecisionTimeline stage: export one Harness run's model decisions to a self-contained HTML viewer.
Invoke-Stage -Name 'DecisionTimeline' -Action {
    if ([string]::IsNullOrWhiteSpace($DecisionTimelineRunDirectory)) {
        # No run specified: refresh the single persistent multi-run panel.
        & $HarnessPowerShell -NoProfile -File $decisionTimelineScript
    } else {
        & $HarnessPowerShell -NoProfile -File $decisionTimelineScript -RunDirectory $DecisionTimelineRunDirectory
    }
    if ($LASTEXITCODE -ne 0) { throw "Decision timeline export failed with exit code $LASTEXITCODE." }
}
