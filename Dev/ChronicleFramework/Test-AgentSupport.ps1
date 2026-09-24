function Wait-ForAgentSettlementArrival {
    param(
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$SettlementId,
        [Parameter(Mandatory = $true)][string]$CommandPrefix,
        [int]$TimeoutSeconds = 180,
        [double]$StepDays = 0.25,
        [int]$MaximumSteps = 12
    )

    for ($step = 1; $step -le $MaximumSteps; $step++) {
        $commandId = "$CommandPrefix-step-$step"
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CliPath advance -Days $StepDays -CommandId $commandId -TimeoutSeconds $TimeoutSeconds 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Harness time step '$commandId' failed: $output" }
        try { $receipt = $output | ConvertFrom-Json }
        catch { throw "Harness time step '$commandId' returned invalid JSON: $output" }
        if ($receipt.state.location.currentSettlementId -eq $SettlementId) { return $receipt }
        if ($receipt.state.context.encounterActive) {
            throw "Unexpected encounter '$($receipt.state.context.encounteredPartyId)' interrupted travel to settlement '$SettlementId'."
        }
    }

    throw "Main party did not arrive at '$SettlementId' within $MaximumSteps explicit Harness time steps."
}
