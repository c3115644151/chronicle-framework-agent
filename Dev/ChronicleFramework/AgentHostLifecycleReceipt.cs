using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Text.RegularExpressions;

namespace ChronicleFramework;

[DataContract]
internal sealed class AgentHostLifecycleReceipt
{
    [DataMember(Name = "status")] public string Status { get; set; }
    [DataMember(Name = "providerModelId")] public string ModelId { get; set; }
    [DataMember(Name = "providerConfigurationSource")] public string ConfigurationSource { get; set; }
    [DataMember(Name = "decisionCount")] public int DecisionCount { get; set; }
    [DataMember(Name = "decisions", EmitDefaultValue = false)] public int DecisionCountAlias { get; set; }
    [DataMember(Name = "actionsExecuted")] public int ActionsExecuted { get; set; }
    [DataMember(Name = "firstDecisionRequiresGoalClassification")] public bool FirstDecisionRequiresGoalClassification { get; set; }
    [DataMember(Name = "firstDecisionListsSupportedGoalClassification")] public bool FirstDecisionListsSupportedGoalClassification { get; set; }
    [DataMember(Name = "firstDecisionListsUnsupportedGoalClassification")] public bool FirstDecisionListsUnsupportedGoalClassification { get; set; }
    [DataMember(Name = "promptTokens")] public long PromptTokens { get; set; }
    [DataMember(Name = "completionTokens")] public long CompletionTokens { get; set; }
    [DataMember(Name = "providerPromptCacheHitTokens")] public long? PromptCacheHitTokens { get; set; }
    [DataMember(Name = "providerPromptCacheMissTokens")] public long? PromptCacheMissTokens { get; set; }
    [DataMember(Name = "providerActualCostEstimateCny")] public double? ActualCostEstimateCny { get; set; }
    [DataMember(Name = "providerReservedCostUpperCny")] public double? ReservedCostUpperBoundCny { get; set; }
    [DataMember(Name = "failureCode")] public string FailureCode { get; set; }
    [DataMember(Name = "failure")] public string Failure { get; set; }
    [DataMember(Name = "error")] public string ErrorCode { get; set; }
    [DataMember(Name = "termination")] public AgentHostLifecycleTermination Termination { get; set; }

    internal static void CaptureForHarness(string output, string errorOutput)
    {
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE") != "agent-host-lifecycle-test") return;
        var repositoryRoot = Environment.GetEnvironmentVariable("CHRONICLE_REPOSITORY_ROOT");
        var evidenceTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(repositoryRoot) || string.IsNullOrWhiteSpace(evidenceTemp)) return;
        try
        {
            var allowedRoot = Path.GetFullPath(Path.Combine(repositoryRoot, "Dev", "ChronicleFramework", "TestResults")) + Path.DirectorySeparatorChar;
            var actualTemp = Path.GetFullPath(evidenceTemp).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!actualTemp.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase) || !Directory.Exists(actualTemp)) return;
            var json = string.IsNullOrWhiteSpace(output) ? errorOutput : output;
            if (string.IsNullOrWhiteSpace(json) || json.Length > 4 * 1024 * 1024) return;
            var serializer = new DataContractJsonSerializer(typeof(AgentHostLifecycleReceipt));
            AgentHostLifecycleReceipt receipt;
            using (var input = new MemoryStream(Encoding.UTF8.GetBytes(json)))
                receipt = (AgentHostLifecycleReceipt)serializer.ReadObject(input);
            receipt.DecisionCount = Math.Max(receipt.DecisionCount, receipt.DecisionCountAlias);
            receipt.DecisionCountAlias = 0;
            using (var file = File.Create(Path.Combine(actualTemp, "AgentHostLifecycleHostReceipt.json")))
                serializer.WriteObject(file, receipt);
        }
        catch (Exception exception)
        {
            var detail = Regex.Replace(exception.Message ?? string.Empty, @"(?i)(bearer\s+)\S+", "$1<redacted>");
            detail = Regex.Replace(detail, @"(?i)((?:api.?key|token|secret)\s*[:=]\s*)[^\s,;]+", "$1<redacted>");
            detail = detail.Replace('|', '/').Replace('\r', ' ').Replace('\n', ' ');
            if (detail.Length > 240) detail = detail.Substring(0, 240);
            ChronicleDiagnostics.Write("harness-agent-host-receipt-failed|type=" + exception.GetType().Name + "|detail=" + detail);
        }
    }
}

[DataContract]
internal sealed class AgentHostLifecycleTermination
{
    [DataMember(Name = "reason")] public string Reason { get; set; }
    [DataMember(Name = "completedByProvider")] public bool CompletedByProvider { get; set; }
    [DataMember(Name = "goalVerified")] public bool GoalVerified { get; set; }
}
