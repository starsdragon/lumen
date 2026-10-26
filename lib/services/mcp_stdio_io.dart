import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local MCP servers are a desktop feature: Android apps cannot execute
/// arbitrary binaries from their sandbox.
bool get supportsStdio =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class McpStdioSession {
  McpStdioSession._(this._process, this._stderrTail);

  final Process _process;
  final StringBuffer _stderrTail;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _nextId = 0;
  bool _closed = false;

  static Future<McpStdioSession> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
  }) async {
    if (command.trim().isEmpty) {
      throw StateError('MCP stdio 命令不能为空。');
    }
    final process = await Process.start(
      command,
      args,
      environment: env.isEmpty ? null : env,
      runInShell: Platform.isWindows,
    );
    final session = McpStdioSession._(process, StringBuffer());
    session._listen();
    return session;
  }

  void _listen() {
    _stdoutSubscription = _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        Map<String, dynamic>? message;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) message = decoded.map((k, v) => MapEntry('$k', v));
        } catch (_) {
          return;
        }
        if (message == null) return;
        final id = message['id'];
        if (id is int && _pending.containsKey(id)) {
          final completer = _pending.remove(id)!;
          if (!completer.isCompleted) completer.complete(message);
        }
      },
      onError: (Object error) => _failAll('读取 MCP stdout 失败：$error'),
      onDone: () => _failAll('MCP 进程已退出。'),
    );
    _stderrSubscription = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) {
      _stderrTail.write(line);
      if (_stderrTail.length > 4000) {
        final text = _stderrTail.toString();
        _stderrTail
          ..clear()
          ..write(text.substring(text.length - 3000));
      }
    });
    _process.exitCode.then((code) {
      _closed = true;
      _failAll('MCP 进程已退出（code=$code）。');
    });
  }

  void _failAll(String message) {
    final details = _stderrTail.toString().trim();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(details.isEmpty ? message : '$message\n$details'));
      }
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_closed) throw StateError('MCP 进程已经退出。');
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    _process.stdin.writeln(payload);
    await _process.stdin.flush();
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pending.remove(id);
        final details = _stderrTail.toString().trim();
        throw StateError(
          'MCP stdio 请求超时：$method${details.isEmpty ? '' : '\n$details'}',
        );
      },
    );
  }

  Future<void> notify(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_closed) return;
    _process.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    }));
    await _process.stdin.flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    try {
      await _process.stdin.close();
    } catch (_) {
      // Ignore.
    }
    _process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!Platform.isWindows) {
      _process.kill(ProcessSignal.sigkill);
    }
  }
}
