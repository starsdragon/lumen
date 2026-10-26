import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/database.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/controllers.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('memory extraction merges profile, deduplicates facts and retrieves context', () async {
    final database = await databaseFactoryMemory.openDatabase('lumen-memory-test.db');
    final repository = AppRepository(AppDatabase(database), SecretStore());
    final controller = MemoriesController(repository);
    await controller.load();

    final changed = await controller.mergeExtraction(
      {
        'profile_updates': {
          'name': '小林',
          'occupation': '产品经理',
          'personality': ['理性', '重视效率'],
          'goals': ['完成职业转型'],
          'thinkingStyle': '先建立框架，再验证假设。',
          'summary': '一位重视效率的产品经理。',
        },
        'memories': [
          {
            'content': '用户是一名产品经理，主要做企业协作工具。',
            'category': 'career',
            'importance': 5,
            'confidence': 0.9,
          },
          {
            'content': '用户喜欢先看结论。',
            'category': 'preference',
            'importance': 4,
            'confidence': 0.8,
          },
        ],
      },
      'conv-1',
    );

    expect(changed, greaterThan(0));
    expect(controller.profile.name, '小林');
    expect(controller.profile.occupation, '产品经理');
    expect(controller.profile.personality, containsAll(['理性', '重视效率']));
    expect(controller.memories.length, 2);

    final duplicateResult = await controller.mergeExtraction(
      {
        'memories': [
          {
            'content': '用户是一名产品经理，主要做企业协作工具。',
            'category': 'career',
            'importance': 5,
            'confidence': 0.95,
          }
        ]
      },
      'conv-2',
    );
    expect(duplicateResult, 0);
    expect(controller.memories.length, 2);

    final relevant = controller.retrieve('产品经理 职业');
    expect(relevant, isNotEmpty);
    expect(relevant.first.content, contains('产品经理'));

    final prompt = controller.buildMemoryPrompt('职业发展');
    expect(prompt, contains('小林'));
    expect(prompt, contains('产品经理'));

    final toolResult = await controller.saveMemoryTool(
      '用户正在考虑转向 AI 产品方向。',
      MemoryCategory.goal,
      5,
    );
    expect(toolResult, contains('已写入'));
    expect(controller.memories.length, 3);

    await database.close();
  });
}
