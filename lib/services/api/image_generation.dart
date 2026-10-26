import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../core/utils.dart';
import '../../data/models.dart';
import 'llm_types.dart';

class GeneratedImage {
  const GeneratedImage({required this.bytes, required this.mime, this.revisedPrompt});

  final Uint8List bytes;
  final String mime;
  final String? revisedPrompt;
}

class ImageGenerationService {
  Future<GeneratedImage> generate({
    required ProviderConfig provider,
    required String apiKey,
    required ModelInfo model,
    required String prompt,
    String aspectRatio = '1:1',
  }) async {
    if (provider.demo) {
      final data = await rootBundle.load('assets/images/demo/demo_art.jpg');
      return GeneratedImage(
        bytes: data.buffer.asUint8List(),
        mime: 'image/jpeg',
        revisedPrompt: '演示图片：接入真实生图模型后，这里会显示模型生成的作品。',
      );
    }
    if (prompt.trim().isEmpty) throw const LlmException('请先输入图片描述。');
    if (apiKey.isEmpty) throw const LlmException('请先配置该厂商的 API Key。');

    if (provider.protocol == LlmProtocol.gemini) {
      return _gemini(provider, apiKey, model, prompt, aspectRatio);
    }
    final host = Uri.tryParse(provider.baseUrl)?.host.toLowerCase() ?? '';
    if (provider.id == 'minimax' || host.contains('minimax')) {
      return _miniMax(provider, apiKey, model, prompt, aspectRatio);
    }
    if (provider.id == 'bailian' || host.contains('dashscope') || host.contains('aliyuncs')) {
      return _dashScope(provider, apiKey, model, prompt, aspectRatio);
    }
    if (provider.id == 'zhipu' || host.contains('bigmodel.cn')) {
      return _zhipu(provider, apiKey, model, prompt, aspectRatio);
    }
    return _openAiCompatible(provider, apiKey, model, prompt, aspectRatio);
  }

  Future<GeneratedImage> _zhipu(
    ProviderConfig provider,
    String apiKey,
    ModelInfo model,
    String prompt,
    String aspectRatio,
  ) async {
    final client = http.Client();
    try {
      final url = Uri.parse(joinApiPath(provider.baseUrl, '/images/generations'));
      final response = await _post(client, url, provider, apiKey, {
        'model': model.id,
        'prompt': prompt,
        'size': zhipuSize(aspectRatio),
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response.body, response.statusCode);
      }
      final json = _decode(response.body);
      final data = json['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        final item = (data.first as Map).map((k, v) => MapEntry('$k', v));
        final b64 = item['b64_json']?.toString();
        if (b64 != null && b64.isNotEmpty) {
          return GeneratedImage(bytes: base64Decode(b64), mime: 'image/png');
        }
        final imageUrl = item['url']?.toString();
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return _downloadImage(client, imageUrl, null);
        }
      }
      throw LlmException(_messageFrom(json) ?? '智谱没有返回图片。');
    } finally {
      client.close();
    }
  }

  Future<GeneratedImage> _openAiCompatible(
    ProviderConfig provider,
    String apiKey,
    ModelInfo model,
    String prompt,
    String aspectRatio,
  ) async {
    final client = http.Client();
    try {
      final url = Uri.parse(joinApiPath(provider.baseUrl, '/images/generations'));
      var body = <String, dynamic>{
        'model': model.id,
        'prompt': prompt,
        'n': 1,
        'size': _openAiSize(aspectRatio),
        'response_format': 'b64_json',
      };
      var response = await _post(client, url, provider, apiKey, body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorText = response.body;
        final lower = errorText.toLowerCase();
        if (lower.contains('response_format') || lower.contains('b64_json')) {
          body = Map<String, dynamic>.from(body)..remove('response_format');
          response = await _post(client, url, provider, apiKey, body);
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response.body, response.statusCode);
      }
      final json = _decode(response.body);
      final data = json['data'];
      if (data is! List || data.isEmpty || data.first is! Map) {
        throw LlmException(_messageFrom(json) ?? '生图接口没有返回图片。');
      }
      final item = (data.first as Map).map((k, v) => MapEntry('$k', v));
      final revised = item['revised_prompt']?.toString();
      final b64 = item['b64_json']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        return GeneratedImage(bytes: base64Decode(b64), mime: 'image/png', revisedPrompt: revised);
      }
      final imageUrl = item['url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return _downloadImage(client, imageUrl, revised);
      }
      throw LlmException(_messageFrom(json) ?? '生图接口返回了空结果。');
    } finally {
      client.close();
    }
  }

  Future<GeneratedImage> _miniMax(
    ProviderConfig provider,
    String apiKey,
    ModelInfo model,
    String prompt,
    String aspectRatio,
  ) async {
    final client = http.Client();
    try {
      final url = Uri.parse(joinApiPath(provider.baseUrl, '/image_generation'));
      var body = <String, dynamic>{
        'model': model.id,
        'prompt': prompt,
        'aspect_ratio': aspectRatio,
        'response_format': 'base64',
        'n': 1,
        'prompt_optimizer': true,
      };
      var response = await _post(client, url, provider, apiKey, body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final lower = response.body.toLowerCase();
        if (lower.contains('response_format') || lower.contains('base64')) {
          body = Map<String, dynamic>.from(body)..['response_format'] = 'url';
          response = await _post(client, url, provider, apiKey, body);
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response.body, response.statusCode);
      }
      final json = _decode(response.body);
      final baseResp = json['base_resp'];
      if (baseResp is Map && (baseResp['status_code'] as num?)?.toInt() != 0) {
        throw LlmException('${baseResp['status_msg'] ?? '生图失败'}');
      }
      final data = json['data'];
      if (data is Map) {
        final images = data['image_base64'];
        if (images is List && images.isNotEmpty) {
          return GeneratedImage(bytes: base64Decode('${images.first}'), mime: 'image/jpeg');
        }
        if (images is String && images.isNotEmpty) {
          return GeneratedImage(bytes: base64Decode(images), mime: 'image/jpeg');
        }
        final urls = data['image_urls'];
        if (urls is List && urls.isNotEmpty) {
          return _downloadImage(client, '${urls.first}', null);
        }
      }
      throw LlmException(_messageFrom(json) ?? 'MiniMax 没有返回图片。');
    } finally {
      client.close();
    }
  }

  Future<GeneratedImage> _dashScope(
    ProviderConfig provider,
    String apiKey,
    ModelInfo model,
    String prompt,
    String aspectRatio,
  ) async {
    final client = http.Client();
    try {
      final base = Uri.parse(provider.baseUrl);
      final origin = '${base.scheme}://${base.authority}';
      final createUri = Uri.parse('$origin/api/v1/services/aigc/text2image/image-synthesis');
      final body = {
        'model': model.id,
        'input': {'prompt': prompt},
        'parameters': {'size': _dashScopeSize(aspectRatio), 'n': 1},
      };
      final createResponse = await _post(
        client,
        createUri,
        provider,
        apiKey,
        body,
        extraHeaders: {'X-DashScope-Async': 'enable'},
      );
      if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
        throw _apiError(createResponse.body, createResponse.statusCode);
      }
      final created = _decode(createResponse.body);
      final output = created['output'];
      final taskId = output is Map ? output['task_id']?.toString() : null;
      if (taskId == null || taskId.isEmpty) {
        throw LlmException(_messageFrom(created) ?? '通义万相没有返回任务 ID。');
      }
      final taskUri = Uri.parse('$origin/api/v1/tasks/$taskId');
      for (var attempt = 0; attempt < 45; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final response = await client.get(taskUri, headers: _headers(provider, apiKey)).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _apiError(response.body, response.statusCode);
        }
        final json = _decode(response.body);
        final taskOutput = json['output'];
        if (taskOutput is! Map) continue;
        final status = '${taskOutput['task_status'] ?? ''}'.toUpperCase();
        if (status == 'SUCCEEDED') {
          final results = taskOutput['results'];
          if (results is List) {
            for (final raw in results) {
              if (raw is Map && raw['url'] != null) {
                return _downloadImage(client, '${raw['url']}', null);
              }
            }
          }
          throw const LlmException('任务完成，但没有返回图片。');
        }
        if (status == 'FAILED' || status == 'CANCELED' || status == 'UNKNOWN') {
          throw LlmException('${taskOutput['message'] ?? '生图任务失败（$status）'}');
        }
      }
      throw const LlmException('生图任务超时，请稍后重试。');
    } finally {
      client.close();
    }
  }

  Future<GeneratedImage> _gemini(
    ProviderConfig provider,
    String apiKey,
    ModelInfo model,
    String prompt,
    String aspectRatio,
  ) async {
    final client = http.Client();
    try {
      final url = Uri.parse(geminiGenerateUrl(provider.baseUrl, model.id, stream: false));
      final response = await _post(client, url, provider, apiKey, {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
          'imageConfig': {'aspectRatio': aspectRatio},
        },
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response.body, response.statusCode);
      }
      final json = _decode(response.body);
      final candidates = json['candidates'];
      if (candidates is List) {
        for (final candidate in candidates) {
          if (candidate is! Map) continue;
          final content = candidate['content'];
          if (content is! Map) continue;
          final parts = content['parts'];
          if (parts is! List) continue;
          for (final rawPart in parts) {
            if (rawPart is! Map) continue;
            final inline = rawPart['inlineData'] ?? rawPart['inline_data'];
            if (inline is Map) {
              final data = inline['data']?.toString();
              if (data != null && data.isNotEmpty) {
                return GeneratedImage(
                  bytes: base64Decode(data),
                  mime: '${inline['mimeType'] ?? inline['mime_type'] ?? 'image/png'}',
                );
              }
            }
          }
        }
      }
      throw LlmException(_messageFrom(json) ?? 'Gemini 没有返回图片。');
    } finally {
      client.close();
    }
  }

  Future<http.Response> _post(
    http.Client client,
    Uri uri,
    ProviderConfig provider,
    String apiKey,
    Map<String, dynamic> body, {
    Map<String, String> extraHeaders = const {},
  }) {
    return client
        .post(
          uri,
          headers: {..._headers(provider, apiKey), ...extraHeaders},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
  }

  Map<String, String> _headers(ProviderConfig provider, String apiKey) {
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
      ...provider.customHeaders,
    };
    if (provider.protocol == LlmProtocol.gemini) {
      headers.putIfAbsent('x-goog-api-key', () => apiKey);
    } else if (provider.protocol == LlmProtocol.anthropic) {
      headers.putIfAbsent('x-api-key', () => apiKey);
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers.putIfAbsent('authorization', () => 'Bearer $apiKey');
    }
    return headers;
  }

  Future<GeneratedImage> _downloadImage(
    http.Client client,
    String url,
    String? revisedPrompt,
  ) async {
    if (!isSafeRemoteUrl(url)) {
      throw const LlmException('返回的图片地址不安全，已拒绝下载。');
    }
    var current = Uri.parse(url);
    http.Response? response;
    for (var hop = 0; hop < 5; hop++) {
      if (!isSafeRemoteUrl(current.toString())) {
        throw const LlmException('图片跳转到了不安全的地址，已拒绝下载。');
      }
      final request = http.Request('GET', current)..followRedirects = false;
      request.headers['User-Agent'] = 'Lumen/1.0';
      final streamed = await client.send(request).timeout(const Duration(seconds: 60));
      if (const [301, 302, 303, 307, 308].contains(streamed.statusCode)) {
        final location = streamed.headers['location'];
        await streamed.stream.drain<void>();
        if (location == null || location.isEmpty) {
          throw const LlmException('图片服务器返回了无效跳转。');
        }
        current = current.resolve(location);
        continue;
      }
      response = http.Response.bytes(
        await streamed.stream.toBytes().timeout(const Duration(seconds: 60)),
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
      break;
    }
    if (response == null) {
      throw const LlmException('图片跳转次数过多，已停止下载。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException('图片下载失败（HTTP ${response.statusCode}）。');
    }
    if (response.bodyBytes.length > 30 * 1024 * 1024) {
      throw const LlmException('图片超过 30MB，已取消下载。');
    }
    final mime = (response.headers['content-type'] ?? 'image/png').split(';').first;
    return GeneratedImage(
      bytes: response.bodyBytes,
      mime: mime.startsWith('image/') ? mime : 'image/png',
      revisedPrompt: revisedPrompt,
    );
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      // Fall through.
    }
    throw LlmException('无法解析生图响应：${body.length > 300 ? '${body.substring(0, 300)}…' : body}');
  }

  String? _messageFrom(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map && error['message'] != null) return '${error['message']}';
    final baseResp = json['base_resp'];
    if (baseResp is Map && baseResp['status_msg'] != null) return '${baseResp['status_msg']}';
    if (json['message'] != null) return '${json['message']}';
    if (json['msg'] != null) return '${json['msg']}';
    return null;
  }

  LlmException _apiError(String body, int statusCode) {
    String message = '生图请求失败（HTTP $statusCode）';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final parsed = _messageFrom(decoded.map((k, v) => MapEntry('$k', v)));
        if (parsed != null && parsed.isNotEmpty) message = parsed;
      }
    } catch (_) {
      if (body.trim().isNotEmpty) {
        message = '$message：${body.length > 300 ? '${body.substring(0, 300)}…' : body}';
      }
    }
    return LlmException(message, statusCode: statusCode);
  }
}

String _openAiSize(String ratio) => switch (ratio) {
      '3:4' || '9:16' => '1024x1536',
      '4:3' || '16:9' => '1536x1024',
      _ => '1024x1024',
    };

String _dashScopeSize(String ratio) => switch (ratio) {
      '3:4' => '768*1024',
      '4:3' => '1024*768',
      '9:16' => '720*1280',
      '16:9' => '1280*720',
      _ => '1024*1024',
    };

String zhipuSize(String ratio) => switch (ratio) {
      '3:4' => '864x1152',
      '4:3' => '1152x864',
      '9:16' => '720x1440',
      '16:9' => '1440x720',
      _ => '1024x1024',
    };
