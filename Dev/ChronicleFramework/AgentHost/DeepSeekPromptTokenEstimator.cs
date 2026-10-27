using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.ML.Tokenizers;

namespace ChronicleFramework.AgentHost;

internal sealed record DeepSeekInputTokenEstimate(int TokenizerTokens, int RawRequestTokens, int ReservedTokens, string Method);

internal static class DeepSeekPromptTokenEstimator
{
    internal const string OfficialTokenizerAssetSha256 = "E7310D1DAFE0A86D8A5629FE78A7C763760F651DB9B8682718A1781DCD6FE495";
    private const string TokenizerResourceName = "ChronicleFramework.AgentHost.deepseek_v4_tokenizer.zip";
    private const double ReservationMargin = 1.15d;
    private const int ServiceProtocolOverheadTokens = 256;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static readonly Lazy<BpeTokenizer> DeepSeekBpe = new(CreateTokenizer, LazyThreadSafetyMode.ExecutionAndPublication);

    internal static DeepSeekInputTokenEstimate EstimateRequest(string requestBody, string systemPrompt, string userContent,
        IReadOnlyDictionary<string, object?> providerPayload)
    {
        ArgumentNullException.ThrowIfNull(requestBody);
        ArgumentNullException.ThrowIfNull(systemPrompt);
        ArgumentNullException.ThrowIfNull(userContent);
        ArgumentNullException.ThrowIfNull(providerPayload);
        try
        {
            var tokenizer = DeepSeekBpe.Value;
            var renderedChat = "<｜begin▁of▁sentence｜>" + systemPrompt + "<｜User｜>" + userContent + "<｜Assistant｜>";
            var renderedChatTokens = tokenizer.CountTokens(renderedChat);
            var structuredMetadata = providerPayload
                .Where(pair => pair.Key is "tools" or "tool_choice" or "response_format")
                .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal);
            var structuredMetadataTokens = structuredMetadata.Count == 0
                ? 0
                : tokenizer.CountTokens(JsonSerializer.Serialize(structuredMetadata, JsonOptions));
            var tokenizerTokens = checked(renderedChatTokens + structuredMetadataTokens);
            var rawRequestTokens = tokenizer.CountTokens(requestBody);
            var reservedTokens = checked((int)Math.Ceiling(tokenizerTokens * ReservationMargin) + ServiceProtocolOverheadTokens);
            return new DeepSeekInputTokenEstimate(tokenizerTokens, rawRequestTokens, reservedTokens, "deepseek-v4-chat-template-plus-structured-metadata");
        }
        catch
        {
            // Preserve the previous conservative bound if an embedded model asset or tokenizer fails.
            var utf8Bytes = Encoding.UTF8.GetByteCount(requestBody);
            return new DeepSeekInputTokenEstimate(utf8Bytes, utf8Bytes, utf8Bytes, "utf8-byte-fallback");
        }
    }

    internal static IReadOnlyList<object> RunContractSelfTests()
    {
        var tokenizer = DeepSeekBpe.Value;
        var cjk = tokenizer.CountTokens("这是一次骑砍战役观察。");
        if (cjk != 9)
            throw new AgentHostException("deepseek-tokenizer-cjk-self-test-failed", "The pinned DeepSeek tokenizer did not reproduce its known CJK sample count.");
        var body = "{\"model\":\"deepseek-flash\",\"messages\":[{\"role\":\"system\",\"content\":\"Choose an action.\"},{\"role\":\"user\",\"content\":\"{\\\"x\\\":1}\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\"}}],\"tool_choice\":\"required\"}";
        var payload = new Dictionary<string, object?> { ["model"] = "deepseek-flash", ["tools"] = new[] { new { type = "function", function = new { name = "f" } } }, ["tool_choice"] = "required" };
        var estimate = EstimateRequest(body, "Choose an action.", "{\"x\":1}", payload);
        if (estimate.Method != "deepseek-v4-chat-template-plus-structured-metadata" || estimate.TokenizerTokens <= 0 ||
            estimate.RawRequestTokens <= 0 || estimate.ReservedTokens != (int)Math.Ceiling(estimate.TokenizerTokens * ReservationMargin) + ServiceProtocolOverheadTokens)
            throw new AgentHostException("deepseek-tokenizer-self-test-failed", "The pinned DeepSeek tokenizer did not estimate chat text, structured metadata, and its conservative reservation margin.");
        return [
            new { scenario = "deepseek-tokenizer-estimates-chat-and-tool-metadata-with-margin", tokenizerInputTokens = estimate.TokenizerTokens, rawBodyTokens = estimate.RawRequestTokens, reservedInputTokens = estimate.ReservedTokens, passed = true },
            new { scenario = "deepseek-tokenizer-byte-level-cjk-count", cjkTokens = cjk, passed = true }
        ];
    }

    private static BpeTokenizer CreateTokenizer()
    {
        using var resource = typeof(DeepSeekPromptTokenEstimator).Assembly.GetManifestResourceStream(TokenizerResourceName)
            ?? throw new AgentHostException("deepseek-tokenizer-resource-missing", "The pinned DeepSeek tokenizer asset is missing from AgentHost.");
        using var compressed = new MemoryStream();
        resource.CopyTo(compressed);
        var assetBytes = compressed.ToArray();
        var assetHash = Convert.ToHexString(SHA256.HashData(assetBytes));
        if (!string.Equals(assetHash, OfficialTokenizerAssetSha256, StringComparison.Ordinal))
            throw new AgentHostException("deepseek-tokenizer-resource-hash-mismatch", "The bundled DeepSeek tokenizer asset did not match its reviewed SHA-256.");

        compressed.Position = 0;
        using var archive = new ZipArchive(compressed, ZipArchiveMode.Read, leaveOpen: false);
        var tokenizerEntry = archive.GetEntry("deepseek_v4_tokenizer/tokenizer.json")
            ?? throw new AgentHostException("deepseek-tokenizer-json-missing", "The bundled DeepSeek tokenizer archive did not contain tokenizer.json.");
        using var tokenizerStream = tokenizerEntry.Open();
        using var document = JsonDocument.Parse(tokenizerStream);
        var root = document.RootElement;
        var model = root.GetProperty("model");
        if (!string.Equals(model.GetProperty("type").GetString(), "BPE", StringComparison.Ordinal))
            throw new AgentHostException("deepseek-tokenizer-model-type-unsupported", "The bundled DeepSeek tokenizer is not a reviewed BPE model.");

        var vocabulary = model.GetProperty("vocab").EnumerateObject()
            .Select(property => new KeyValuePair<string, int>(property.Name, property.Value.GetInt32()))
            .ToArray();
        var merges = model.GetProperty("merges").EnumerateArray()
            .Select(entry => entry.ValueKind == JsonValueKind.String ? entry.GetString()! : string.Join(" ", entry.EnumerateArray().Select(part => part.GetString())))
            .ToArray();
        var specialTokens = root.GetProperty("added_tokens").EnumerateArray()
            .Where(entry => entry.TryGetProperty("special", out var special) && special.GetBoolean())
            .ToDictionary(entry => entry.GetProperty("content").GetString()!, entry => entry.GetProperty("id").GetInt32(), StringComparer.Ordinal);
        var preTokenizers = root.GetProperty("pre_tokenizer").GetProperty("pretokenizers").EnumerateArray().ToArray();
        if (preTokenizers.Length < 3)
            throw new AgentHostException("deepseek-tokenizer-pretokenizer-unsupported", "The bundled DeepSeek tokenizer has an unsupported pre-tokenizer sequence.");
        var patterns = preTokenizers.Take(3)
            .Select(entry => entry.GetProperty("pattern").GetProperty("Regex").GetString()!)
            .Select(pattern => "(?:" + pattern + ")");
        var preTokenizerPattern = string.Join("|", patterns);
        var preTokenizer = new RegexPreTokenizer(
            new Regex(preTokenizerPattern, RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1)), specialTokens);
        var options = new BpeOptions(vocabulary)
        {
            Merges = merges,
            SpecialTokens = specialTokens,
            PreTokenizer = preTokenizer,
            ByteLevel = true,
            BeginningOfSentenceToken = "<｜begin▁of▁sentence｜>",
            EndOfSentenceToken = "<｜end▁of▁sentence｜>"
        };
        return BpeTokenizer.Create(options);
    }
}
