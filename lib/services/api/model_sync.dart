import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils.dart';
import '../../data/models.dart';
import 'llm_types.dart';

class ModelSyncService {
  Future<List<ModelInfo>> fetchModels(ProviderConfig provider, String apiKey) async {
    if (provider.demo) return provider.models;
    if (provider.baseUrl.trim().isEmpty) {
      throw const LlmException('请先填写 Base URL。');
    }
    final client = http.Client();
    try {
      final (uri, headers) = _requestFor(provider, apiKey);
      final response = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LlmException(
          '获取模型列表失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
          details: _shortBody(response.body),
        );
      }
      final decoded = jsonDecode(response.body);
      final fetched = switch (provider.protocol) {
        LlmProtocol.openai => _parseOpenAi(decoded, provider),
        LlmProtocol.anthropic => _parseAnthropic(decoded, provider),
        LlmProtocol.gemini => _parseGemini(decoded, provider),
      };
      if (fetched.isEmpty) {
        throw const LlmException('平台返回了空的模型列表。');
      }
      return _mergeWithExisting(fetched, provider);
    } finally {
      client.close();
    }
  }

  (Uri, Map<String, String>) _requestFor(ProviderConfig provider, String apiKey) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'Lumen/1.0',
      ...provider.customHeaders,
    };
    switch (provider.protocol) {
      case LlmProtocol.openai:
        headers.putIfAbsent('Authorization', () => 'Bearer $apiKey');
        return (Uri.parse(modelsUrlForOpenAi(provider.baseUrl)), headers);
      case LlmProtocol.anthropic:
        headers.putIfAbsent('x-api-key', () => apiKey);
        headers['anthropic-version'] = '2023-06-01';
        return (Uri.parse(anthropicModelsUrl(provider.baseUrl)), headers);
      case LlmProtocol.gemini:
        headers.putIfAbsent('x-goog-api-key', () => apiKey);
        final base = geminiModelsUrl(provider.baseUrl);
        final uri = Uri.parse(base);
        return (
          uri.replace(queryParameters: {...uri.queryParameters, 'pageSize': '1000'}),
          headers,
        );
    }
  }

  List<ModelInfo> _parseOpenAi(Object? decoded, ProviderConfig provider) {
    final models = <ModelInfo>[];
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final id = '${raw['id'] ?? raw['model'] ?? ''}';
          if (id.isEmpty) continue;
          if (_looksLikeEmbedding(id)) continue;
          final existing = provider.models.where((m) => m.id == id).firstOrNull;
          models.add(
            _inferModel(
              id: id,
              name: '${raw['display_name'] ?? raw['name'] ?? existing?.name ?? humanizeModelId(id)}',
              context: _contextFrom(raw) ?? existing?.contextWindow ?? 131072,
              provider: provider,
              existing: existing,
            ),
          );
        }
      }
    }
    return models;
  }

  List<ModelInfo> _parseAnthropic(Object? decoded, ProviderConfig provider) {
    final models = <ModelInfo>[];
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final id = '${raw['id'] ?? ''}';
          if (id.isEmpty) continue;
          final existing = provider.models.where((m) => m.id == id).firstOrNull;
          models.add(
            _inferModel(
              id: id,
              name: '${raw['display_name'] ?? existing?.name ?? humanizeModelId(id)}',
              context: (raw['context_window'] as num?)?.toInt() ?? existing?.contextWindow ?? 200000,
              provider: provider,
              existing: existing,
            ),
          );
        }
      }
    }
    return models;
  }

  List<ModelInfo> _parseGemini(Object? decoded, ProviderConfig provider) {
    final models = <ModelInfo>[];
    if (decoded is Map) {
      final data = decoded['models'];
      if (data is List) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final fullName = '${raw['name'] ?? ''}';
          final id = fullName.replaceFirst(RegExp(r'^models/'), '');
          if (id.isEmpty) continue;
          final methods = (raw['supportedGenerationMethods'] as List?)?.map((e) => '$e').toList() ?? const [];
          if (methods.isNotEmpty && !methods.contains('generateContent')) continue;
          final existing = provider.models.where((m) => m.id == id).firstOrNull;
          models.add(
            _inferModel(
              id: id,
              name: '${raw['displayName'] ?? existing?.name ?? humanizeModelId(id)}',
              context: (raw['inputTokenLimit'] as num?)?.toInt() ?? existing?.contextWindow ?? 1000000,
              provider: provider,
              existing: existing,
            ),
          );
        }
      }
    }
    return models;
  }

  ModelInfo _inferModel({
    required String id,
    required String name,
    required int context,
    required ProviderConfig provider,
    ModelInfo? existing,
  }) {
    final image = _looksLikeImageModel(id);
    final lower = id.toLowerCase();
    final vision = !image &&
        (existing?.vision ??
            RegExp(r'(^|[-_/])(vl|vision|4v)([-_/]|$)').hasMatch(lower) ||
                lower.contains('gpt-4o') ||
                lower.contains('gpt-5') ||
                lower.contains('gpt-6') ||
                lower.contains('o3') ||
                lower.contains('o4') ||
                lower.contains('claude') ||
                lower.contains('gemini') ||
                lower.contains('grok') ||
                lower.contains('kimi-latest') ||
                lower.contains('kimi-k2.') ||
                lower.contains('kimi-k3') ||
                lower.contains('glm-4v') ||
                lower.contains('glm-5') ||
                lower.contains('qwen-vl') ||
                lower.contains('qwen3-vl') ||
                lower.contains('qwen3.7') ||
                lower.contains('qwen3.8') ||
                lower.contains('minimax-vl') ||
                lower.contains('minimax-m3') ||
                lower.contains('deepseek-v4') ||
                lower.contains('mimo') ||
                lower.contains('step-5') ||
                lower.contains('pixtral') ||
                lower.contains('llava'));
    final reasoning = !image &&
        (existing?.reasoning ??
            RegExp(
              r'(reason|thinking|qwq|qwen3|glm-[45]|deepseek-(chat|v4|reasoner)|kimi-k2|minimax-m2|gpt-5|o[134]|claude|gemini-[234]|grok-[34]|magistral)',
            ).hasMatch(lower));
    return ModelInfo(
      id: id,
      name: name.trim().isEmpty ? humanizeModelId(id) : name.trim(),
      contextWindow: context,
      vision: vision,
      reasoning: reasoning,
      tools: !image,
      imageGeneration: image,
      source: 'remote',
    );
  }

  List<ModelInfo> _mergeWithExisting(List<ModelInfo> fetched, ProviderConfig provider) {
    final byId = <String, ModelInfo>{for (final model in fetched) model.id: model};
    for (final existing in provider.models) {
      if (existing.imageGeneration && !byId.containsKey(existing.id)) {
        byId[existing.id] = existing;
      }
    }
    final result = byId.values.toList();
    result.sort((a, b) {
      if (a.imageGeneration != b.imageGeneration) return a.imageGeneration ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  int? _contextFrom(Map<dynamic, dynamic> raw) {
    for (final key in ['context_length', 'context_window', 'max_context_length', 'inputTokenLimit', 'max_input_tokens']) {
      final value = raw[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    final architecture = raw['architecture'];
    if (architecture is Map) {
      for (final key in ['context_length', 'context_window']) {
        final value = architecture[key];
        if (value is num) return value.toInt();
      }
    }
    return null;
  }

  bool _looksLikeEmbedding(String id) {
    final lower = id.toLowerCase();
    return lower.contains('embedding') ||
        lower.contains('embed-') ||
        lower.contains('text-embedding') ||
        lower.contains('bge-') ||
        lower.contains('gte-');
  }

  bool _looksLikeImageModel(String id) {
    final lower = id.toLowerCase();
    return RegExp(
      r'(cogview|image-01|wanx|t2i|text2image|text-to-image|gpt-image|dall-e|imagen|flux|stable-diffusion|sdxl|seedream|kolors|hunyuan-image|qwen-image|recraft|ideogram|gemini.*-image)',
    ).hasMatch(lower);
  }

  String _shortBody(String body) => body.length > 500 ? '${body.substring(0, 500)}…' : body;
}
