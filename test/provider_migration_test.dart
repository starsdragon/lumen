import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/database.dart';
import 'package:lumen/data/models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('legacy OpenCode Zen preset migrates to the Go subscription endpoint', () async {
    final raw = await databaseFactoryMemory.openDatabase('lumen-provider-migration.db');
    final database = AppDatabase(raw);
    await database.seedProvidersIfNeeded();

    final legacy = ProviderConfig(
      id: 'opencode',
      name: 'OpenCode Go',
      protocol: LlmProtocol.openai,
      baseUrl: 'https://opencode.ai/zen/v1',
      builtin: true,
      hasKey: true,
      models: const [
        ModelInfo(id: 'claude-sonnet-4-5', name: 'Old Model'),
      ],
    );
    await database.saveProvider(legacy);

    final providers = await database.loadProviders();
    final migrated = providers.firstWhere((p) => p.id == 'opencode');
    expect(migrated.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(migrated.docsUrl, 'https://opencode.ai/docs/go');
    expect(migrated.models.any((m) => m.id == 'deepseek-v4.1-flash'), isTrue);
    expect(migrated.models.any((m) => m.id == 'claude-sonnet-4-5'), isFalse);
    expect(migrated.modelsSyncedAt, isNull);

    await raw.close();
  });
}
