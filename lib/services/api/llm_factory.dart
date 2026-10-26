import '../../data/models.dart';
import 'anthropic_client.dart';
import 'demo_client.dart';
import 'gemini_client.dart';
import 'llm_types.dart';
import 'openai_client.dart';

class LlmClientFactory {
  const LlmClientFactory();

  LlmClient forProvider(ProviderConfig provider) {
    if (provider.demo) return DemoClient();
    return switch (provider.protocol) {
      LlmProtocol.openai => OpenAiClient(),
      LlmProtocol.anthropic => AnthropicClient(),
      LlmProtocol.gemini => GeminiClient(),
    };
  }
}
