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
    [DataMember(Name = "hostExitCode", EmitDefaultValue = false)] public int? HostExitCode { get; set; }
    [DataMember(Name = "providerModelId")] public string ModelId { get; set; }
    [DataMember(Name = "providerConfigurationSource")] public string ConfigurationSource { get; set; }
    [DataMember(Name = "decisionCount")] public int? DecisionCount { get; set; }
    [DataMember(Name = "decisions", EmitDefaultValue = false)] public int? DecisionCountAlias { get; set; }
    [DataMember(Name = "actionsExecuted")] public int? ActionsExecuted { get; set; }
    [DataMember(Name = "firstDecisionRequiresGoalClassification")] public bool? FirstDecisionRequiresGoalClassification { get; set; }
    [DataMember(Name = "firstDecisionListsSupportedGoalClassification")] public bool? FirstDecisionListsSupportedGoalClassification { get; set; }
    [DataMember(Name = "firstDecisionListsUnsupportedGoalClassification")] public bool? FirstDecisionListsUnsupportedGoalClassification { get; set; }
    [DataMember(Name = "promptTokens")] public long? PromptTokens { get; set; }
    [DataMember(Name = "completionTokens")] public long? CompletionTokens { get; set; }
    [DataMember(Name = "providerPromptCacheHitTokens")] public long? PromptCacheHitTokens { get; set; }
    [DataMember(Name = "providerPromptCacheMissTokens")] public long? PromptCacheMissTokens { get; set; }
    [DataMember(Name = "providerActualCostEstimateCny")] public double? ActualCostEstimateCny { get; set; }
    [DataMember(Name = "providerReservedCostUpperCny")] public double? ReservedCostUpperBoundCny { get; set; }
    [DataMember(Name = "failureCode")] public string FailureCode { get; set; }
    [DataMember(Name = "failure")] public string Failure { get; set; }
    [DataMember(Name = "error")] public string ErrorCode { get; set; }
    [DataMember(Name = "message")] public string Message { get; set; }
    [DataMember(Name = "exceptionType")] public string ExceptionType { get; set; }
    [DataMember(Name = "providerSelfTestDetail")] public string ProviderSelfTestDetail { get; set; }
    [DataMember(Name = "termination")] public AgentHostLifecycleTermination Termination { get; set; }

    internal static AgentHostLifecycleReceipt CaptureForHarness(string output, string errorOutput, int hostExitCode)
    {
        var harnessMode = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_MODE");
        if (harnessMode is not ("agent-host-lifecycle-test" or "fresh-campaign-renown")) return null;
        var repositoryRoot = Environment.GetEnvironmentVariable("CHRONICLE_REPOSITORY_ROOT");
        var evidenceTemp = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_TEMP");
        if (string.IsNullOrWhiteSpace(repositoryRoot) || string.IsNullOrWhiteSpace(evidenceTemp)) return null;
        try
        {
            var allowedRoot = Path.GetFullPath(Path.Combine(repositoryRoot, "Dev", "ChronicleFramework", "TestResults")) + Path.DirectorySeparatorChar;
            var actualTemp = Path.GetFullPath(evidenceTemp).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!actualTemp.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase) || !Directory.Exists(actualTemp)) return null;
            var receipt = TryDeserializeReceipt(output) ?? TryDeserializeReceipt(errorOutput);
            if (receipt == null)
            {
                ChronicleDiagnostics.Write("harness-agent-host-receipt-unavailable|exitCode=" + hostExitCode.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                    "|stdoutPresent=" + (!string.IsNullOrWhiteSpace(output)) + "|stderrPresent=" + (!string.IsNullOrWhiteSpace(errorOutput)));
                return null;
            }
            receipt.HostExitCode = hostExitCode;
            receipt.Message = SanitizeDiagnostic(receipt.Message);
            receipt.Failure = SanitizeDiagnostic(receipt.Failure);
            receipt.ProviderSelfTestDetail = SanitizeDiagnostic(receipt.ProviderSelfTestDetail);
            receipt.DecisionCount = Math.Max(receipt.DecisionCount ?? 0, receipt.DecisionCountAlias ?? 0);
            receipt.DecisionCountAlias = null;
            var serializer = new DataContractJsonSerializer(typeof(AgentHostLifecycleReceipt));
            using (var file = File.Create(Path.Combine(actualTemp, "AgentHostLifecycleHostReceipt.json")))
                serializer.WriteObject(file, receipt);
            return receipt;
        }
        catch (Exception exception)
        {
            var detail = Regex.Replace(exception.Message ?? string.Empty, @"(?i)(bearer\s+)\S+", "$1<redacted>");
            detail = Regex.Replace(detail, @"(?i)((?:api.?key|token|secret)\s*[:=]\s*)[^\s,;]+", "$1<redacted>");
            detail = detail.Replace('|', '/').Replace('\r', ' ').Replace('\n', ' ');
            if (detail.Length > 240) detail = detail.Substring(0, 240);
            ChronicleDiagnostics.Write("harness-agent-host-receipt-failed|exitCode=" + hostExitCode.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                "|type=" + exception.GetType().Name + "|detail=" + detail);
            return null;
        }
    }

    private static AgentHostLifecycleReceipt TryDeserializeReceipt(string text)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length > 4 * 1024 * 1024) return null;
        var candidates = new System.Collections.Generic.List<string> { text.Trim() };
        var lines = text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        for (var index = lines.Length - 1; index >= 0; index--)
            if (lines[index].Length <= 4 * 1024 * 1024) candidates.Add(lines[index].Trim());
        var serializer = new DataContractJsonSerializer(typeof(AgentHostLifecycleReceipt));
        foreach (var candidate in candidates)
        {
            try
            {
                using (var input = new MemoryStream(Encoding.UTF8.GetBytes(candidate)))
                {
                    var receipt = serializer.ReadObject(input) as AgentHostLifecycleReceipt;
                    if (receipt != null && (!string.IsNullOrWhiteSpace(receipt.Status) || !string.IsNullOrWhiteSpace(receipt.ErrorCode) ||
                        !string.IsNullOrWhiteSpace(receipt.FailureCode))) return receipt;
                }
            }
            catch { }
        }
        return null;
    }

    internal static string SanitizeDiagnostic(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return value;
        value = Regex.Replace(value, @"(?i)(bearer\s+)\S+", "$1<redacted>");
        value = Regex.Replace(value, @"(?i)sk-[A-Za-z0-9_-]+", "<redacted>");
        value = Regex.Replace(value, @"(?i)((?:api.?key|token|secret)\s*[:=]\s*)[^\s,;]+", "$1<redacted>");
        value = value.Replace('|', '/').Replace('\r', ' ').Replace('\n', ' ').Trim();
        return value.Length > 240 ? value.Substring(0, 240) : value;
    }
}

[DataContract]
internal sealed class AgentHostLifecycleTermination
{
    [DataMember(Name = "reason")] public string Reason { get; set; }
    [DataMember(Name = "completedByProvider")] public bool? CompletedByProvider { get; set; }
    [DataMember(Name = "goalVerified")] public bool? GoalVerified { get; set; }
}
