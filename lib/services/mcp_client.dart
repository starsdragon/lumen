import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/utils.dart';
import '../data/models.dart';
import 'api/sse.dart';
import 'mcp_stdio_web.dart' if (dart.library.io) 'mcp_stdio_io.dart';

class McpException implements Exception {
  const McpException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}

class McpService {
  bool get supportsLocalStdio => supportsStdio;

  Future<List<McpToolInfo>> listTools(McpServerConfig server) async {
    try {
      final session = await _open(server);
      try {
        await session.initialize();
        final tools = <McpToolInfo>[];
        String? cursor;
        for (var page = 0; page < 10; page++) {
          final result = await session.request(
            'tools/list',
            cursor == null ? const {} : {'cursor': cursor},
          );
          final list = result['tools'];
          if (list is List) {
            for (final raw in list) {
              if (raw is! Map) continue;
              final map = raw.map((k, v) => MapEntry('$k', v));
              final name = '${map['name'] ?? ''}';
              if (name.isEmpty) continue;
              final schema = map['inputSchema'] is Map
                  ? (map['inputSchema'] as Map).map((k, v) => MapEntry('$k', v))
                  : <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}};
              tools.add(
                McpToolInfo(
                  name: name,
                  description: '${map['description'] ?? ''}',
                  inputSchema: schema,
                ),
              );
            }
          }
          final next = result['nextCursor']?.toString();
          if (next == null || next.isEmpty || next == cursor) break;
          cursor = next;
        }
        return tools;
      } finally {
        await session.close();
      }
    } on McpException {
      rethrow;
    } catch (error) {
      throw McpException('连接 MCP 服务器失败：$error');
    }
  }

  Future<String> callTool(
    McpServerConfig server,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final session = await _open(server);
      try {
        await session.initialize();
        final result = await session.request('tools/call', {
          'name': toolName,
          'arguments': arguments,
        });
        final buffer = StringBuffer();
        final content = result['content'];
        if (content is List) {
          for (final raw in content) {
            if (raw is! Map) continue;
            final item = raw.map((k, v) => MapEntry('$k', v));
            final type = '${item['type'] ?? ''}';
            if (type == 'text' && item['text'] != null) {
              buffer.writeln('${item['text']}');
            } else if (type == 'resource' && item['resource'] is Map) {
              final resource = item['resource'] as Map;
              if (resource['text'] != null) buffer.writeln('${resource['text']}');
              if (resource['uri'] != null) buffer.writeln('[资源] ${resource['uri']}');
            } else if (type == 'image') {
              buffer.writeln('[图片内容，已省略]');
            } else {
              buffer.writeln('[$type] ${item['text'] ?? ''}');
            }
          }
        }
        if (buffer.isEmpty && result['structuredContent'] != null) {
          buffer.write(const JsonEncoder.withIndent('  ').convert(result['structuredContent']));
        }
        final text = buffer.toString().trim();
        if (result['isError'] == true) {
          throw McpException(text.isEmpty ? 'MCP 工具返回错误。' : text);
        }
        return text.isEmpty ? '（工具没有返回文本内容）' : text;
      } finally {
        await session.close();
      }
    } on McpException {
      rethrow;
    } catch (error) {
      throw McpException('调用 MCP 工具失败：$error');
    }
  }

  Future<_McpSession> _open(McpServerConfig server) async {
    switch (server.transport) {
      case McpTransport.streamableHttp:
        return _HttpMcpSession(server);
      case McpTransport.sse:
        return _SseMcpSession(server);
      case McpTransport.stdio:
        if (!supportsStdio) {
          throw const McpException('stdio MCP 仅支持桌面端，当前平台无法启动本地进程。');
        }
        return _StdioMcpSession(server);
    }
  }
}

abstract class _McpSession {
  Future<void> initialize();
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params);
  Future<void> notify(String method, [Map<String, dynamic> params = const {}]);
  Future<void> close();
}

class _HttpMcpSession implements _McpSession {
  _HttpMcpSession(this.server);

  final McpServerConfig server;
  final http.Client _client = http.Client();
  String? _sessionId;
  int _nextId = 0;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'accept': 'application/json, text/event-stream',
        ...server.headers,
        'mcp-session-id': ?_sessionId,
      };

  @override
  Future<void> initialize() async {
    try {
      await _initializeWith(_McpServiceProtocol.current);
    } on McpException {
      await _initializeWith(_McpServiceProtocol.fallback);
    }
  }

  Future<void> _initializeWith(String version) async {
    final response = await _postRaw({
      'jsonrpc': '2.0',
      'id': ++_nextId,
      'method': 'initialize',
      'params': {
        'protocolVersion': version,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'Lumen', 'version': '1.0.1'},
      },
    });
    _readSessionId(response);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpException(
        'MCP 初始化失败（HTTP ${response.statusCode}）',
        details: _short(body),
      );
    }
    _checkJsonError(body);
    await notify('notifications/initialized');
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = ++_nextId;
    final response = await _postRaw({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    _readSessionId(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw McpException(
        'MCP 请求失败（HTTP ${response.statusCode}）',
        details: _short(body),
      );
    }
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('event-stream')) {
      await for (final event in parseSse(response.stream.timeout(const Duration(seconds: 60)))) {
        final result = _parseMessage(event.data);
        if (result != null && result['id'] == id) {
          return _unwrapResult(result);
        }
      }
      throw McpException('MCP 连接提前结束，没有收到 $method 的响应。');
    }
    final body = await response.stream.bytesToString();
    if (body.trim().isEmpty) {
      throw McpException('MCP 服务器没有返回 $method 的响应。');
    }
    final decoded = _decode(body);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map && item['id'] == id) {
          return _unwrapResult(item.map((k, v) => MapEntry('$k', v)));
        }
      }
    } else if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry('$k', v));
      if (map['id'] == id) return _unwrapResult(map);
    }
    throw McpException('无法解析 MCP 响应。', details: _short(body));
  }

  @override
  Future<void> notify(String method, [Map<String, dynamic> params = const {}]) async {
    final response = await _postRaw({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
    _readSessionId(response);
    await response.stream.drain<void>();
  }

  Future<http.StreamedResponse> _postRaw(Map<String, dynamic> body) {
    final uri = Uri.parse(server.url.trim());
    if (!isHttpUrl(server.url) || uri.host.isEmpty) {
      throw const McpException('MCP 服务器地址无效。');
    }
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);
    return _client.send(request).timeout(const Duration(seconds: 30));
  }

  void _readSessionId(http.StreamedResponse response) {
    final id = response.headers['mcp-session-id'] ?? response.headers['Mcp-Session-Id'];
    if (id != null && id.isNotEmpty) _sessionId = id;
  }

  Map<String, dynamic> _unwrapResult(Map<String, dynamic> message) {
    final error = message['error'];
    if (error is Map) {
      throw McpException('${error['message'] ?? 'MCP 返回错误'}');
    }
    final result = message['result'];
    if (result is Map) return result.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

class _SseMcpSession implements _McpSession {
  _SseMcpSession(this.server);

  final McpServerConfig server;
  final http.Client _client = http.Client();
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  StreamSubscription<dynamic>? _subscription;
  Uri? _endpoint;
  int _nextId = 0;
  Object? _streamError;

  Map<String, String> get _headers => {
        'accept': 'text/event-stream, application/json',
        'content-type': 'application/json',
        ...server.headers,
      };

  @override
  Future<void> initialize() async {
    await _startStream();
    try {
      await _initializeWith(_McpServiceProtocol.current);
    } on McpException {
      await _initializeWith(_McpServiceProtocol.fallback);
    }
  }

  Future<void> _initializeWith(String version) async {
    await request('initialize', {
      'protocolVersion': version,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'Lumen', 'version': '1.0.1'},
    });
    await notify('notifications/initialized');
  }

  Future<void> _startStream() async {
    final uri = Uri.parse(server.url.trim());
    if (!isHttpUrl(server.url) || uri.host.isEmpty) {
      throw const McpException('MCP SSE 地址无效。');
    }
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers);
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpException('连接 MCP SSE 失败（HTTP ${response.statusCode}）。');
    }
    final endpointCompleter = Completer<void>();
    _subscription = parseSse(response.stream.timeout(const Duration(seconds: 300))).listen(
      (event) {
        final data = event.data.trim();
        if (event.event == 'endpoint' || data.startsWith('/')) {
          if (data.isNotEmpty) {
            _endpoint = uri.resolve(data);
            if (!endpointCompleter.isCompleted) endpointCompleter.complete();
          }
          return;
        }
        final message = _parseMessage(data);
        if (message == null) return;
        final id = message['id'];
        if (id is int && _pending.containsKey(id)) {
          final pending = _pending.remove(id)!;
          if (!pending.isCompleted) pending.complete(message);
        }
      },
      onError: (Object error) {
        _streamError = error;
        for (final pending in _pending.values) {
          if (!pending.isCompleted) pending.completeError(McpException('MCP SSE 断开：$error'));
        }
        _pending.clear();
        if (!endpointCompleter.isCompleted) {
          endpointCompleter.completeError(McpException('MCP SSE 连接失败：$error'));
        }
      },
      cancelOnError: false,
    );
    await endpointCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw const McpException('MCP SSE 没有返回 endpoint 事件。'),
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_endpoint == null) await _startStream();
    if (_streamError != null) throw McpException('MCP SSE 连接不可用：$_streamError');
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final request = http.Request('POST', _endpoint!);
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _pending.remove(id);
      throw McpException(
        'MCP 请求失败（HTTP ${response.statusCode}）',
        details: _short(body),
      );
    }
    if (body.trim().isNotEmpty) {
      final decoded = _decode(body);
      if (decoded is Map && decoded['id'] == id) {
        _pending.remove(id);
        if (!completer.isCompleted) {
          completer.complete(decoded.map((k, v) => MapEntry('$k', v)));
        }
      }
    }
    final message = await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(id);
        throw McpException('MCP SSE 请求超时：$method');
      },
    );
    final error = message['error'];
    if (error is Map) throw McpException('${error['message'] ?? 'MCP 返回错误'}');
    final result = message['result'];
    return result is Map ? result.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};
  }

  @override
  Future<void> notify(String method, [Map<String, dynamic> params = const {}]) async {
    if (_endpoint == null) return;
    final request = http.Request('POST', _endpoint!);
    request.headers.addAll(_headers);
    request.body = jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params});
    final response = await _client.send(request).timeout(const Duration(seconds: 20));
    await response.stream.drain<void>();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _client.close();
  }
}

class _StdioMcpSession implements _McpSession {
  _StdioMcpSession(this.server);

  final McpServerConfig server;
  late McpStdioSession _session;

  @override
  Future<void> initialize() async {
    _session = await McpStdioSession.start(
      command: server.command,
      args: server.args,
      env: server.env,
    );
    try {
      await _session.request('initialize', {
        'protocolVersion': _McpServiceProtocol.current,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'Lumen', 'version': '1.0.1'},
      });
    } on McpException {
      await _session.request('initialize', {
        'protocolVersion': _McpServiceProtocol.fallback,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'Lumen', 'version': '1.0.1'},
      });
    }
    await _session.notify('notifications/initialized');
  }

  @override
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params) async {
    final result = await _session.request(method, params);
    final error = result['error'];
    if (error is Map) throw McpException('${error['message'] ?? 'MCP 返回错误'}');
    final payload = result['result'];
    return payload is Map ? payload.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};
  }

  @override
  Future<void> notify(String method, [Map<String, dynamic> params = const {}]) =>
      _session.notify(method, params);

  @override
  Future<void> close() => _session.close();
}

class _McpServiceProtocol {
  static const current = '2025-03-26';
  static const fallback = '2024-11-05';
}

Map<String, dynamic>? _parseMessage(String data) {
  final trimmed = data.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
  } catch (_) {
    return null;
  }
  return null;
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

void _checkJsonError(String body) {
  final decoded = _decode(body);
  if (decoded is Map && decoded['error'] is Map) {
    final error = decoded['error'] as Map;
    throw McpException('${error['message'] ?? 'MCP 初始化失败'}');
  }
}

String _short(String body) => body.length > 500 ? '${body.substring(0, 500)}…' : body;
