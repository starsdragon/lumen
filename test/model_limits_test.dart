import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/database.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/controllers.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('model token overrides survive settings serialization', () {
    final settings = AppSettings(
      modelLimits: {
        'opencode::deepseek-v4.1-flash': const ModelTokenLimit(
          inputTokens: 1000000,
          outputTokens: 32768,
        ),
      },
    );

    final decoded = AppSettings.fromJson(settings.toJson());
    final limit = decoded.modelLimits['opencode::deepseek-v4.1-flash'];

    expect(limit, isNotNull);
    expect(limit!.inputTokens, 1000000);
    expect(limit.outputTokens, 32768);
    expect(limit.outputLimit, 32768);
    expect(limit.isValid, isTrue);
  });

  test('invalid persisted limits are ignored', () {
    final decoded = AppSettings.fromJson({
      'modelLimits': {
        'p::m': {'inputTokens': 100, 'outputTokens': 10},
        'p::tooBig': {'inputTokens': 4096, 'outputTokens': 8192},
        'p::valid': {'inputTokens': 131072, 'outputTokens': 0},
      }
    });

    expect(decoded.modelLimits.containsKey('p::m'), isFalse);
    expect(decoded.modelLimits.containsKey('p::tooBig'), isFalse);
    expect(decoded.modelLimits['p::valid']?.inputTokens, 131072);
    expect(decoded.modelLimits['p::valid']?.outputLimit, 32768);
  });

  test('settings controller persists and clears a model override', () async {
    final database = await databaseFactoryMemory.openDatabase('lumen-model-limits.db');
    final repository = AppRepository(AppDatabase(database), SecretStore());
    final controller = SettingsController(repository);

    await controller.setModelLimit(
      'opencode',
      'deepseek-v4.1-flash',
      const ModelTokenLimit(inputTokens: 1000000, outputTokens: 32768),
    );

    final persisted = await repository.db.loadSettings();
    expect(persisted.modelLimits['opencode::deepseek-v4.1-flash']?.inputTokens, 1000000);
    expect(controller.modelLimitFor('opencode', 'deepseek-v4.1-flash')?.outputTokens, 32768);

    await controller.setModelLimit('opencode', 'deepseek-v4.1-flash', null);
    final cleared = await repository.db.loadSettings();
    expect(cleared.modelLimits.containsKey('opencode::deepseek-v4.1-flash'), isFalse);
    await database.close();
  });

  test('effective limits prefer explicit overrides and one million input works', () {
    const model = ModelInfo(
      id: 'deepseek-v4.1-flash',
      name: 'DeepSeek V4.1 Flash',
      contextWindow: 1000000,
    );
    const override = ModelTokenLimit(inputTokens: 900000, outputTokens: 64000);

    expect(effectiveInputLimit(model, null), 1000000);
    expect(effectiveOutputLimit(model, null), 32768);
    expect(effectiveInputLimit(model, override), 900000);
    expect(effectiveOutputLimit(model, override), 64000);
    expect(autoOutputTokenLimit(1000), 4096);
    expect(autoOutputTokenLimit(131072), 32768);
    expect(autoOutputTokenLimit(2000000), 32768);
  });
}
