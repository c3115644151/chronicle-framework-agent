using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace ChronicleFramework;

[DataContract]
internal sealed class AgentHostLifecycleReceipt
{
    [DataMember(Name = "status")] public string Status { get; set; }
    [DataMember(Name = "providerModelId")] public string ModelId { get; set; }
    [DataMember(Name = "providerConfigurationSource")] public string ConfigurationSource { get; set; }
    [DataMember(Name = "decisionCount")] public int DecisionCount { get; set; }
    [DataMember(Name = "actionsExecuted")] public int ActionsExecuted { get; set; }
    [DataMember(Name = "promptTokens")] public long PromptTokens { get; set; }
    [DataMember(Name = "completionTokens")] public long CompletionTokens { get; set; }
    [DataMember(Name = "failureCode")] public string FailureCode { get; set; }
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
            using (var file = File.Create(Path.Combine(actualTemp, "AgentHostLifecycleHostReceipt.json")))
                serializer.WriteObject(file, receipt);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("harness-agent-host-receipt-failed|type=" + exception.GetType().Name);
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
