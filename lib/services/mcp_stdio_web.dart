/// Web builds cannot launch local processes. The MCP UI still exposes remote
/// HTTP/SSE servers; this stub keeps the shared client code compiling.
bool get supportsStdio => false;

class McpStdioSession {
  static Future<McpStdioSession> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
  }) async {
    throw UnsupportedError('stdio MCP is unavailable on the web build.');
  }

  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic> params = const {}]) async {
    throw UnsupportedError('stdio MCP is unavailable on the web build.');
  }

  Future<void> notify(String method, [Map<String, dynamic> params = const {}]) async {
    throw UnsupportedError('stdio MCP is unavailable on the web build.');
  }

  Future<void> close() async {}
}
