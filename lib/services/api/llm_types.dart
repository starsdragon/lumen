import '../../data/models.dart';

class LlmRequest {
  const LlmRequest({
    required this.provider,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.messages,
    this.tools = const [],
    this.reasoningLevel = ReasoningLevel.auto,
    this.maxTokens = 16384,
    this.temperature = 0.7,
    this.includeReasoningHistory = true,
    this.sessionId = '',
  });

  final ProviderConfig provider;
  final String apiKey;
  final ModelInfo model;
  final String systemPrompt;
  final List<LlmMessage> messages;
  final List<ToolDefinition> tools;
  final ReasoningLevel reasoningLevel;
  final int maxTokens;
  final double temperature;
  final bool includeReasoningHistory;

  /// Stable per-conversation id. OpenCode Go requires it in
  /// `x-opencode-session` for routing and prompt caching.
  final String sessionId;
}

class LlmMessage {
  const LlmMessage({
    required this.role,
    this.text = '',
    this.images = const [],
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.toolIsError = false,
    this.reasoning = '',
    this.rawContent,
  });

  final ChatRole role;
  final String text;
  final List<Attachment> images;
  final List<LlmToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final bool toolIsError;
  final String reasoning;

  /// Provider-native assistant blocks (Anthropic thinking/signature, Gemini
  /// thoughtSignature). Only valid for the immediately following tool call.
  final List<Map<String, dynamic>>? rawContent;

  factory LlmMessage.user(String text, {List<Attachment> images = const []}) =>
      LlmMessage(role: ChatRole.user, text: text, images: images);

  factory LlmMessage.assistant(String text, {List<LlmToolCall> toolCalls = const [], String reasoning = '', List<Map<String, dynamic>>? rawContent}) =>
      LlmMessage(
        role: ChatRole.assistant,
        text: text,
        toolCalls: toolCalls,
        reasoning: reasoning,
        rawContent: rawContent,
      );

  factory LlmMessage.toolResult(
    String toolCallId,
    String toolName,
    String result, {
    bool isError = false,
  }) =>
      LlmMessage(
        role: ChatRole.tool,
        text: result,
        toolCallId: toolCallId,
        toolName: toolName,
        toolIsError: isError,
      );
}

class LlmToolCall {
  const LlmToolCall({required this.id, required this.name, required this.argumentsJson});

  final String id;
  final String name;
  final String argumentsJson;
}

sealed class LlmEvent {
  const LlmEvent();
}

class ReasoningDelta extends LlmEvent {
  const ReasoningDelta(this.text);
  final String text;
}

class TextDelta extends LlmEvent {
  const TextDelta(this.text);
  final String text;
}

class ToolCallStarted extends LlmEvent {
  const ToolCallStarted({required this.id, required this.name});
  final String id;
  final String name;
}

class ToolCallArgumentsDelta extends LlmEvent {
  const ToolCallArgumentsDelta({required this.id, required this.delta});
  final String id;
  final String delta;
}

class ToolCallCompleted extends LlmEvent {
  const ToolCallCompleted(this.call);
  final LlmToolCall call;
}

class UsageReported extends LlmEvent {
  const UsageReported({this.inputTokens = 0, this.outputTokens = 0});
  final int inputTokens;
  final int outputTokens;
}

class TurnCompleted extends LlmEvent {
  const TurnCompleted({this.finishReason = 'stop', this.rawAssistantContent});
  final String finishReason;
  final List<Map<String, dynamic>>? rawAssistantContent;
}

class StreamFailure extends LlmEvent {
  const StreamFailure(this.message, {this.details, this.statusCode});
  final String message;
  final String? details;
  final int? statusCode;
}

class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final String? details;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (statusCode != null) buffer.write(' (HTTP $statusCode)');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n${details!.trim()}');
    }
    return buffer.toString();
  }
}

abstract class LlmClient {
  Stream<LlmEvent> stream(LlmRequest request);
}

String joinApiPath(String base, String path) {
  final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.endsWith(path)) return normalized;
  return '$normalized$path';
}

/// OpenCode Go is a subscription endpoint at `/zen/go/v1`; `/zen/v1` is the
/// pay-as-you-go Zen endpoint with a separate balance.
bool usesOpenCodeGo(ProviderConfig provider) {
  if (provider.id == 'opencode') return true;
  final uri = Uri.tryParse(provider.baseUrl);
  return uri != null &&
      uri.host.contains('opencode.ai') &&
      uri.path.contains('/zen/go');
}

String chatCompletionsUrl(String base) {
  if (base.contains('/chat/completions')) return base;
  return joinApiPath(base, '/chat/completions');
}

String modelsUrlForOpenAi(String base) {
  var normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.endsWith('/chat/completions')) {
    normalized = normalized.substring(0, normalized.length - '/chat/completions'.length);
  }
  return joinApiPath(normalized, '/models');
}

String anthropicMessagesUrl(String base) {
  final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.endsWith('/messages')) return normalized;
  if (RegExp(r'/v\d+(?:beta)?$').hasMatch(normalized)) return '$normalized/messages';
  return '$normalized/v1/messages';
}

String anthropicModelsUrl(String base) {
  final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.endsWith('/models')) return normalized;
  if (RegExp(r'/v\d+(?:beta)?$').hasMatch(normalized)) return '$normalized/models';
  return '$normalized/v1/models';
}

String geminiModelsUrl(String base) {
  final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.endsWith('/models')) return normalized;
  if (normalized.endsWith('/v1beta') || normalized.endsWith('/v1')) {
    return '$normalized/models';
  }
  return '$normalized/v1beta/models';
}

String geminiGenerateUrl(String base, String model, {bool stream = true}) {
  final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
  final method = stream ? 'streamGenerateContent?alt=sse' : 'generateContent';
  if (normalized.contains('/v1beta') || normalized.endsWith('/v1')) {
    return '$normalized/models/$model:$method';
  }
  return '$normalized/v1beta/models/$model:$method';
}

String stripDataUrlPrefix(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  return comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
}

String dataUrlMime(String dataUrl, {String fallback = 'image/jpeg'}) {
  final match = RegExp(r'^data:([^;,]+)').firstMatch(dataUrl);
  return match?.group(1) ?? fallback;
}

/// Some provider APIs reject `additionalProperties`/`$schema` in JSON schemas.
Map<String, dynamic> sanitizeSchemaForGemini(Object? schema) {
  if (schema is! Map) return {'type': 'object', 'properties': <String, dynamic>{}};
  final out = <String, dynamic>{};
  for (final entry in schema.entries) {
    final key = '${entry.key}';
    if (['additionalProperties', r'$schema', r'$id', 'strict', 'default', 'examples'].contains(key)) {
      continue;
    }
    if (key == 'type') {
      final value = entry.value;
      if (value is List) {
        final nonNull = value.where((e) => '$e' != 'null').toList();
        if (nonNull.isNotEmpty) out['type'] = '${nonNull.first}'.toUpperCase();
        if (value.length != nonNull.length) out['nullable'] = true;
      } else if (value is String) {
        out['type'] = value.toUpperCase();
      }
    } else if (key == 'properties' && entry.value is Map) {
      final props = (entry.value as Map).map(
        (k, v) => MapEntry('$k', sanitizeSchemaForGemini(v)),
      );
      out['properties'] = props;
    } else if (key == 'items') {
      out['items'] = sanitizeSchemaForGemini(entry.value);
    } else if (key == 'anyOf' || key == 'oneOf') {
      // Gemini 3 supports a subset; prefer a permissive object instead of
      // failing the whole request for a complex MCP schema.
      out['type'] = 'OBJECT';
    } else if (key == 'required' && entry.value is List) {
      out['required'] = entry.value.map((e) => '$e').toList();
    } else if (entry.value is Map) {
      out[key] = sanitizeSchemaForGemini(entry.value);
    } else if (entry.value is List) {
      out[key] = entry.value;
    } else {
      out[key] = entry.value;
    }
  }
  if (!out.containsKey('type') && out.containsKey('properties')) {
    out['type'] = 'OBJECT';
  }
  return out;
}
