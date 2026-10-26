import 'dart:async';

import '../core/utils.dart';
import '../data/models.dart';
import 'api/llm_factory.dart';
import 'api/llm_types.dart';

class MemoryExtractor {
  MemoryExtractor(this.clients);

  final LlmClientFactory clients;

  Future<Map<String, dynamic>?> extract({
    required ProviderConfig provider,
    required String apiKey,
    required ModelInfo model,
    required String transcript,
    required UserProfile profile,
    required List<MemoryItem> existingMemories,
    String sessionId = '',
  }) async {
    if (provider.demo || transcript.trim().isEmpty) return null;
    final existingProfile = profile.toPrompt();
    final existingFacts = existingMemories
        .take(40)
        .map((m) => '- [${m.category.name}] ${m.content}')
        .join('\n');
    final system = '''
你是一个隐私谨慎的长期记忆整理器。你要从对话中提取"未来仍然有用"的稳定信息，而不是复述整段聊天。

只提取用户明确说过、或从上下文可以高置信度确认的信息：
- 不要推测健康、政治、宗教、性取向等敏感属性；
- 不要把临时情绪、一次性任务、助手自己的观点当成用户画像；
- 不要保存密码、身份证号、银行卡、精确住址等敏感数据；
- 如果信息与旧记忆冲突，以对话中更新的信息为准，并在 memories 中写入更新后的事实。

只输出一个 JSON 对象，不要 Markdown 代码块，不要解释。结构：
{
  "profile_updates": {
    "name": "用户的称呼（若有）",
    "occupation": "职业/角色",
    "location": "常驻城市或地区",
    "education": "教育背景",
    "personality": ["稳定性格特点"],
    "expertise": ["专业领域/技能"],
    "interests": ["长期兴趣"],
    "values": ["价值观"],
    "goals": ["正在推进的目标"],
    "communicationStyle": ["沟通偏好，例如先给结论"],
    "thinkingStyle": "思维方式的一句话描述",
    "summary": "2-4 句综合画像"
  },
  "memories": [
    {"content": "第三人称的一句事实", "category": "identity|career|preference|opinion|goal|skill|relationship|other", "importance": 1, "confidence": 0.8}
  ],
  "conversation_summary": "一句话总结这段对话在聊什么"
}

规则：
- 字段没有信息就省略，或给空字符串/空数组；
- memories 最多 6 条；只写新的或需要更新的，不要重复已有记忆；
- importance 1-5，5 表示长期关键信息；
- 所有内容用中文。

已有用户画像：
${existingProfile.isEmpty ? '（暂无）' : existingProfile}

已有长期记忆：
${existingFacts.isEmpty ? '（暂无）' : existingFacts}
''';

    final client = clients.forProvider(provider);
    final buffer = StringBuffer();
    var failure = '';
    try {
      await for (final event in client
          .stream(
            LlmRequest(
              provider: provider,
              apiKey: apiKey,
              model: model,
              systemPrompt: system,
              messages: [
                LlmMessage.user('请分析下面的对话并输出 JSON：\n\n$transcript'),
              ],
              tools: const [],
              reasoningLevel: ReasoningLevel.off,
              maxTokens: 3000,
              temperature: 0.2,
              sessionId: sessionId,
            ),
          )
          .timeout(const Duration(seconds: 120))) {
        if (event is TextDelta) buffer.write(event.text);
        if (event is StreamFailure) failure = event.message;
      }
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
    if (failure.isNotEmpty || buffer.isEmpty) return null;
    return parseJsonLoose(buffer.toString());
  }
}
