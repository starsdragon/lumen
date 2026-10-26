import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/database.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/controllers.dart';
import 'package:lumen/services/memory_transfer.dart';
import 'package:sembast/sembast_memory.dart';

Future<MemoriesController> _controller(String name) async {
  final database = await databaseFactoryMemory.openDatabase(name);
  final controller = MemoriesController(AppRepository(AppDatabase(database), SecretStore()));
  await controller.load();
  return controller;
}

void main() {
  test('memory bundle round-trips profile and entries', () async {
    final controller = await _controller('lumen-memory-export.db');
    await controller.saveProfile(
      UserProfile(
        name: '小林',
        occupation: '产品经理',
        goals: const ['完成职业转型'],
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await controller.addMemory('用户喜欢先看结论。', category: MemoryCategory.preference, importance: 4);

    final decoded = MemoryBundle.decode(controller.exportBundle().encode());
    expect(decoded.profile.name, '小林');
    expect(decoded.profile.goals, contains('完成职业转型'));
    expect(decoded.memories, hasLength(1));
    expect(decoded.memories.single.category, MemoryCategory.preference);
    expect(decoded.memories.single.importance, 4);
  });

  test('merge imports missing profile fields, deduplicates facts, and replace swaps the library', () async {
    final source = await _controller('lumen-memory-source.db');
    await source.saveProfile(
      UserProfile(name: '小林', occupation: '产品经理', updatedAt: DateTime.utc(2026, 1, 2)),
    );
    await source.addMemory('用户喜欢先看结论。', category: MemoryCategory.preference, importance: 4);
    final bundle = MemoryBundle.decode(source.exportBundle().encode());

    final target = await _controller('lumen-memory-target.db');
    final first = await target.importBundle(bundle, mode: MemoryImportMode.merge);
    expect(first.added, 1);
    expect(target.profile.name, '小林');
    expect(target.profile.occupation, '产品经理');
    expect(target.memories, hasLength(1));

    final duplicate = await target.importBundle(bundle, mode: MemoryImportMode.merge);
    expect(duplicate.added, 0);
    expect(duplicate.skipped, 1);
    expect(target.memories, hasLength(1));

    await target.addMemory('旧记忆', category: MemoryCategory.other);
    final replaced = await target.importBundle(bundle, mode: MemoryImportMode.replace);
    expect(replaced.replaced, isTrue);
    expect(target.memories, hasLength(1));
    expect(target.memories.single.content, '用户喜欢先看结论。');
    expect(target.memories.single.id, isNot(source.memories.single.id));
  });

  test('accepts the legacy full-database record shape and rejects wrong files', () {
    final profile = UserProfile(name: '小林').toJson();
    final memory = MemoryItem(
      id: 'mem-old',
      content: '用户喜欢先看结论。',
      category: MemoryCategory.preference,
      createdAt: DateTime.utc(2026, 1, 1),
    ).toJson();
    final legacy = jsonEncode({
      'app': 'Lumen',
      'profile': {'id': 'profile', 'value': profile},
      'memories': [
        {'id': 'mem-old', 'value': memory},
      ],
    });

    final bundle = MemoryBundle.decode(legacy);
    expect(bundle.profile.name, '小林');
    expect(bundle.memories, hasLength(1));
    expect(MemoryBundle.decode('\uFEFF$legacy').profile.name, '小林');

    expect(
      () => MemoryBundle.decode(jsonEncode({'app': 'Other', 'profile': profile})),
      throwsFormatException,
    );
    expect(
      () => MemoryBundle.decode(jsonEncode({'app': 'Lumen', 'version': 9})),
      throwsFormatException,
    );
  });
}
