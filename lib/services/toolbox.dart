import 'dart:convert';

import '../core/utils.dart';
import '../data/models.dart';
import 'mcp_client.dart';
import 'search_service.dart';

typedef SaveMemoryTool = Future<String> Function(
  String content,
  MemoryCategory category,
  int importance,
);
typedef SearchMemoryTool = Future<String> Function(String query);

class Toolbox {
  Toolbox({
    required this.searchConfig,
    required this.credentials,
    required this.webSearchEnabled,
    required this.memoryEnabled,
    required this.searchService,
    required this.mcpService,
    required this.mcpServers,
    required this.mcpTools,
    this.saveMemory,
    this.searchMemory,
  });

  final SearchConfig searchConfig;
  final SearchCredentials credentials;
  final bool webSearchEnabled;
  final bool memoryEnabled;
  final SearchService searchService;
  final McpService mcpService;
  final List<McpServerConfig> mcpServers;
  final Map<String, List<McpToolInfo>> mcpTools;
  final SaveMemoryTool? saveMemory;
  final SearchMemoryTool? searchMemory;

  final Map<String, _McpToolBinding> _mcpBindings = {};

  List<ToolDefinition> get definitions {
    final tools = <ToolDefinition>[];
    if (webSearchEnabled && searchConfig.provider != SearchProvider.none) {
      tools.add(
        const ToolDefinition(
          name: 'web_search',
          displayName: '联网搜索',
          description:
              '搜索公开网页，获取最新信息。适合新闻、价格、版本、人物近况、政策等可能变化的问题。返回网页标题、链接和正文摘要。',
          inputSchema: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': '搜索关键词，尽量具体；不要包含“帮我搜索”之类的指令。',
              },
              'max_results': {
                'type': 'integer',
                'description': '返回结果数量，1-8，默认 6。',
                'minimum': 1,
                'maximum': 8,
              },
            },
            'required': ['query'],
          },
        ),
      );
      tools.add(
        const ToolDefinition(
          name: 'fetch_url',
          displayName: '读取网页',
          description: '读取一个公开网页的正文。仅用于搜索结果摘要不足、需要核对细节的情况。',
          inputSchema: {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '要读取的 http/https 地址'},
            },
            'required': ['url'],
          },
        ),
      );
    }
    if (memoryEnabled) {
      tools.add(
        const ToolDefinition(
          name: 'save_memory',
          displayName: '写入长期记忆',
          description:
              '当用户明确表达一个稳定、未来有用的事实、偏好或目标时，将其保存到长期记忆。不要保存临时情绪、一次性任务或敏感推测。',
          inputSchema: {
            'type': 'object',
            'properties': {
              'content': {'type': 'string', 'description': '以第三人称写一句简洁的事实。'},
              'category': {
                'type': 'string',
                'enum': ['identity', 'career', 'preference', 'opinion', 'goal', 'skill', 'relationship', 'other'],
              },
              'importance': {'type': 'integer', 'minimum': 1, 'maximum': 5},
            },
            'required': ['content', 'category'],
          },
        ),
      );
      tools.add(
        const ToolDefinition(
          name: 'search_memory',
          displayName: '检索长期记忆',
          description: '在长期记忆中检索与当前问题相关的信息。仅在需要回忆用户背景时使用。',
          inputSchema: {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '要查找的主题或关键词'},
            },
            'required': ['query'],
          },
        ),
      );
    }

    _mcpBindings.clear();
    final usedNames = tools.map((t) => t.name).toSet();
    for (final server in mcpServers.where((s) => s.enabled)) {
      final toolsForServer = mcpTools[server.id] ?? server.tools;
      if (toolsForServer.isEmpty) continue;
      final serverPart = sanitizeToolName(server.name, prefix: 'server');
      for (final tool in toolsForServer) {
        var exposed = 'mcp__${serverPart}__${sanitizeToolName(tool.name)}';
        if (exposed.length > 64) {
          exposed = sanitizeToolName(exposed);
        }
        var suffix = 2;
        while (usedNames.contains(exposed)) {
          exposed = sanitizeToolName('${exposed}_$suffix');
          suffix++;
        }
        usedNames.add(exposed);
        _mcpBindings[exposed] = _McpToolBinding(server: server, tool: tool);
        tools.add(
          ToolDefinition(
            name: exposed,
            displayName: '${server.name} · ${tool.name}',
            server: server.name,
            description: tool.description.isEmpty
                ? '来自 MCP 服务器 ${server.name} 的工具 ${tool.name}。'
                : '${tool.description}\n（MCP 服务器：${server.name}）',
            inputSchema: tool.inputSchema,
          ),
        );
      }
    }
    return tools;
  }

  Future<ToolOutcome> execute(ToolCallRecord call) async {
    Map<String, dynamic> args = const {};
    try {
      final decoded = jsonDecode(call.argumentsJson.isEmpty ? '{}' : call.argumentsJson);
      if (decoded is Map) args = decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return ToolOutcome(
        text: '工具参数不是合法 JSON，无法执行。',
        isError: true,
        title: call.title,
      );
    }

    try {
      switch (call.name) {
        case 'web_search':
          final query = '${args['query'] ?? ''}'.trim();
          if (query.isEmpty) {
            return ToolOutcome(text: '搜索词为空。', isError: true, title: '联网搜索');
          }
          final limit = (args['max_results'] as num?)?.toInt();
          final config = SearchConfig(
            provider: searchConfig.provider,
            googleCx: searchConfig.googleCx,
            searxBaseUrl: searchConfig.searxBaseUrl,
            maxResults: (limit ?? searchConfig.maxResults).clamp(1, 8),
            fetchPageContent: searchConfig.fetchPageContent,
            includeDomains: searchConfig.includeDomains,
          );
          final hits = await searchService.search(
            query,
            config: config,
            credentials: credentials,
          );
          if (hits.isEmpty) {
            return ToolOutcome(
              text: '没有搜索到相关结果。请换一个更具体的关键词，或直接说明无法确认。',
              title: '联网搜索：$query',
            );
          }
          return ToolOutcome(
            text: _formatHits(hits),
            citations: [
              for (var i = 0; i < hits.length; i++)
                Citation(
                  title: hits[i].title,
                  url: hits[i].url,
                  snippet: hits[i].snippet,
                  index: i + 1,
                  publishedAt: hits[i].publishedAt,
                ),
            ],
            title: '联网搜索：$query',
          );
        case 'fetch_url':
          final url = '${args['url'] ?? ''}'.trim();
          final page = await searchService.fetchPage(url);
          final text = page.content.trim();
          if (text.isEmpty) {
            return ToolOutcome(text: '这个网页没有可读正文。', isError: true, title: '读取网页');
          }
          return ToolOutcome(
            text: '《${page.title}》\n$url\n\n$text',
            title: '读取网页：${page.title.isEmpty ? url : page.title}',
          );
        case 'save_memory':
          if (saveMemory == null) {
            return ToolOutcome(text: '记忆功能当前不可用。', isError: true, title: '写入记忆');
          }
          final content = '${args['content'] ?? ''}'.trim();
          if (content.isEmpty) {
            return ToolOutcome(text: '记忆内容为空。', isError: true, title: '写入记忆');
          }
          final category = MemoryCategory.values.firstWhere(
            (c) => c.name == '${args['category']}',
            orElse: () => MemoryCategory.other,
          );
          final importance = (args['importance'] as num?)?.toInt().clamp(1, 5) ?? 3;
          final message = await saveMemory!(content, category, importance);
          return ToolOutcome(text: message, title: '写入长期记忆');
        case 'search_memory':
          if (searchMemory == null) {
            return ToolOutcome(text: '记忆功能当前不可用。', isError: true, title: '检索记忆');
          }
          final query = '${args['query'] ?? ''}'.trim();
          final result = await searchMemory!(query);
          return ToolOutcome(text: result, title: '检索长期记忆');
      }

      final binding = _mcpBindings[call.name];
      if (binding != null) {
        final result = await mcpService.callTool(
          binding.server,
          binding.tool.name,
          args,
        );
        return ToolOutcome(
          text: result,
          title: '${binding.server.name} · ${binding.tool.name}',
          server: binding.server.name,
        );
      }
      return ToolOutcome(text: '未知工具：${call.name}', isError: true, title: call.name);
    } on SearchException catch (error) {
      return ToolOutcome(
        text: error.message,
        isError: true,
        title: call.title,
      );
    } on McpException catch (error) {
      return ToolOutcome(text: error.message, isError: true, title: call.title);
    } catch (error) {
      return ToolOutcome(
        text: '工具执行失败：$error',
        isError: true,
        title: call.title,
      );
    }
  }

  String _formatHits(List<SearchHit> hits) {
    final buffer = StringBuffer(
      '以下为实时搜索结果。请综合这些资料，先给结论，再分点解释关键事实与差异；'
      '不要在回答中写来源编号、网址或来源列表，来源由应用统一展示。不要只罗列搜索结果。\n\n',
    );
    for (var i = 0; i < hits.length; i++) {
      if (buffer.length > 14000) {
        buffer.writeln('（其余来源已省略，请基于以上资料回答。）');
        break;
      }
      final hit = hits[i];
      buffer.writeln('标题：${hit.title.isEmpty ? hit.url : hit.title}');
      buffer.writeln('链接：${hit.url}');
      if (hit.publishedAt.trim().isNotEmpty) {
        buffer.writeln('时间: ${hit.publishedAt.trim()}');
      }
      final body = (hit.content.isNotEmpty ? hit.content : hit.snippet).trim();
      if (body.isNotEmpty) {
        final limit = i < 3 ? 3000 : 900;
        buffer.writeln(body.length > limit ? '${body.substring(0, limit)}…' : body);
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}

class ToolOutcome {
  const ToolOutcome({
    required this.text,
    this.citations = const [],
    this.isError = false,
    this.title = '',
    this.server = '',
  });

  final String text;
  final List<Citation> citations;
  final bool isError;
  final String title;
  final String server;
}

class _McpToolBinding {
  const _McpToolBinding({required this.server, required this.tool});

  final McpServerConfig server;
  final McpToolInfo tool;
}
