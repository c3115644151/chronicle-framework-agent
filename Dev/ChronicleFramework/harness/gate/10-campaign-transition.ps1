#Requires -Version 7.0

# Campaign transition: same-process Campaign roundtrip, NuGet fallback and package receipts.
# Sources asserted here: AgentHostCampaignTransitionHarness.cs, Test-AgentHostPackage.ps1, Program.cs

$agentHostCampaignTransitionSource = Get-Content (Join-Path $modRoot 'AgentHostCampaignTransitionHarness.cs') -Raw -Encoding UTF8
if ($agentHostLifecycleHarness -notmatch "'CampaignRoundtrip'" -or
    $agentCliSource -notmatch "'save'" -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'save'" -or
    $agentCliSource -notmatch '\-ReturnWhenAccepted' -or
    $agentCliSource -notmatch 'Invoke-ProtocolCommand ''save''.*-ReturnWhenAccepted:\$ReturnWhenAccepted' -or
    $agentHostCampaignTransitionSource -notmatch 'MapScreen\.Instance' -or
    $agentHostCampaignTransitionSource -notmatch 'MapScreen\.OnExit' -or
    $agentHostCampaignTransitionSource -notmatch 'SandBoxSaveHelper\.TryLoadSave' -or
    $agentHostCampaignTransitionSource -notmatch 'CheckMetaDataCompatibilityErrors' -or
    $agentHostCampaignTransitionSource -notmatch 'native-save-helper-inquiry' -or
    $agentHostCampaignTransitionSource -notmatch 'CheckMetaDataCompatibilityErrors' -or
    $agentHostCampaignTransitionSource -notmatch 'OnNativeSaveStateChanged' -or
    $agentHostCampaignTransitionSource -notmatch 'native-save-helper-inquiry' -or
    $agentHostCampaignTransitionSource -notmatch 'AgentBridgeLifecycle' -or
    $agentHostCampaignTransitionSource -notmatch 'CampaignRoundtrip\.proceed' -or
    $agentHostCampaignTransitionSource -notmatch 'agent-host-lifecycle-test' -or
    $agentHostCampaignTransitionSource -notmatch 'CHRONICLE_HARNESS_AGENT_NO_MODEL' -or
    $agentHostCampaignTransitionSource -notmatch 'CHRONICLE_REPOSITORY_ROOT') {
    throw 'The same-process Campaign roundtrip must use the installed Native exit/load path, the fixed disposable fixture, and strict lifecycle/no-model/TestResults gates.'
}
$agentHostPackageSource = Get-Content (Join-Path $stageRoot 'Test-AgentHostPackage.ps1') -Raw -Encoding UTF8
$agentHostProgramSource = Get-Content (Join-Path $agentHostRoot 'Program.cs') -Raw -Encoding UTF8
if ($agentHostPackageSource -notmatch 'NU1900' -or $agentHostPackageSource -notmatch 'NuGetAudit=false' -or
    $agentHostPackageSource -notmatch 'PackageReference' -or
    $agentHostPackageSource -notmatch 'Microsoft.ML.Tokenizers' -or
    $agentHostPackageSource -notmatch '2.0.1' -or
    $agentHostPackageSource -notmatch 'Google.Protobuf' -or
    $agentHostPackageSource -notmatch 'THIRD-PARTY-NOTICES.txt') {
    throw 'NuGet audit fallback must be limited to a failed NU1900 vulnerability feed and the reviewed, pinned tokenizer dependency.'
}
if ($agentHostPackageSource -notmatch 'CompanionObservationProjection' -or
    $agentHostPackageSource -notmatch 'missionBytesSaved' -or
    $agentHostPackageSource -notmatch 'estimatedPromptTokensSaved' -or
    $agentHostPackageSource -notmatch 'RecruitmentPromptCachePrefix' -or
    $agentHostPackageSource -notmatch 'GoldSalePromptCachePrefix' -or
    $agentHostPackageSource -notmatch 'cacheablePrefixTokenGain' -or
    $agentHostPackageSource -notmatch 'ProviderContractSelfTestScenarioCount') {
    throw 'AgentHostPackage must retain structured per-run receipts for Companion observation reduction and PartySize/Gold reusable-prefix token gains.'
}
if (-not (Test-Path -LiteralPath $deepSeekTokenizerAsset -PathType Leaf) -or
    -not (Test-Path -LiteralPath $deepSeekTokenizerLicense -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Microsoft.ML.Tokenizers-LICENSE.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Microsoft.ML.Tokenizers-THIRD-PARTY-NOTICES.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'Google.Protobuf-LICENSE.txt') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $deepSeekTokenizerAsset) 'THIRD-PARTY-NOTICES.txt') -PathType Leaf) -or
    (Get-FileHash -LiteralPath $deepSeekTokenizerAsset -Algorithm SHA256).Hash -ne 'E7310D1DAFE0A86D8A5629FE78A7C763760F651DB9B8682718A1781DCD6FE495' -or
    $deepSeekTokenEstimatorSource -notmatch 'BpeOptions' -or
    $deepSeekTokenEstimatorSource -notmatch 'ByteLevel = true' -or
    $deepSeekTokenEstimatorSource -notmatch 'ReservationMargin' -or
    $deepSeekTokenEstimatorSource -notmatch 'utf8-byte-fallback' -or
    $deepSeekTokenEstimatorSource -notmatch 'OfficialTokenizerAssetSha256' -or
    $providerHostSource -notmatch 'DeepSeekPromptTokenEstimator\.EstimateRequest\(' -or
    $providerProfileTestSource -notmatch 'DeepSeekPromptTokenEstimator\.RunContractSelfTests' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekEstimatedInputTokens' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekRawRequestTokens' -or
    $agentHostHarnessProgressTraceSource -notmatch 'deepSeekReservedInputTokens') {
    throw 'DeepSeek token-cost estimation must use the hash-pinned official tokenizer asset, byte-level BPE, a conservative margin, and its safe byte-bound fallback.'
}
if ($harnessScript -notmatch "'AgentHostPackage'\s*\{ @\('Preflight', 'Build', 'AgentHostPackage'\) \}" -or
    $harnessScript -match "'All'\s*\{[^\r\n]*'AgentHostPackage'" -or
    $agentHostPackageSource -notmatch 'win-x64' -or $agentHostPackageSource -notmatch "'--self-contained',\s*'true'" -or
    $agentHostPackageSource -notmatch 'NUGET_PACKAGES' -or $agentHostPackageSource -notmatch '127\.0\.0\.1:7890' -or
    $agentHostPackageSource -notmatch 'function Test-BoundedTcpPort' -or $agentHostPackageSource -notmatch 'TimeoutMilliseconds = 500' -or $agentHostPackageSource -match 'Test-NetConnection' -or
    $agentHostPackageSource -notmatch 'D:\\ChronicleFramework\\BuildCache\\Packages' -or $agentHostPackageSource -notmatch 'package staging must be outside the source repository' -or
    $agentHostPackageSource -notmatch 'BaseOutputPath' -or
    $agentHostPackageSource -notmatch 'ChronicleAgentHost\.exe' -or $agentHostPackageSource -notmatch 'AgentHostPackageManifest\.json' -or
    $agentHostPackageSource -notmatch '\[switch\]\$RetainRuntimePackage' -or
    $agentHostPackageSource -notmatch '\[string\]\$CleanupPackageRoot' -or
    $agentHostPackageSource -notmatch 'Cleanup-only mode refuses while a Bannerlord or Agent Host process may still use the package' -or
    $agentHostPackageSource -notmatch 'PackageArtifactsRetained = \[bool\]\$RetainRuntimePackage' -or
    $agentHostPackageSource -notmatch 'AgentHostRuntimePackage\.json' -or
    $agentHostPackageSource -notmatch 'RuntimeExecutablePath' -or
    $agentHostPackageSource -notmatch 'Invoke-StaleAgentHostPackageCleanup' -or
    $agentHostPackageSource -notmatch 'OlderThanHours = 24' -or
    $agentHostPackageSource -notmatch 'CreationTimeUtc -lt \$cutoffUtc' -or
    $agentHostPackageSource -notmatch 'StalePackageCleanup = \$stalePackageCleanup' -or
    $agentHostPackageSource -notmatch 'Remove-Item -LiteralPath \$resolvedPackageRoot -Recurse -Force' -or
    $agentHostPackageSource -notmatch 'Refusing to remove package staging outside the exact unique Chronicle Agent Host cache directory' -or
    $agentHostPackageSource -notmatch 'Invoke-PackagedHostUnboundParentProbe' -or $agentHostPackageSource -notmatch 'UnboundParentRejected' -or
    $agentHostProviderSelfTestSource -notmatch 'RunParentProcessContractSelfTestsAsync' -or
    $agentHostProviderSelfTestSource -notmatch 'mcm-start-request-rejects-invalid-snapshot-without-profile-fallback' -or
    $agentHostProgramSource -notmatch 'campaign-parent-not-running' -or
    $agentHostProgramSource -notmatch '--package-health' -or $agentHostProgramSource -notmatch '--version') {
    throw 'Agent Host packaging must be an opt-in win-x64 self-contained publish, use D: NuGet cache/proxy port 7890, and directly verify the packaged Host without the .NET CLI.'
}
