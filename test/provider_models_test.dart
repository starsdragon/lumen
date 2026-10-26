import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/services/controllers.dart';

void main() {
  test('manual models survive sync and can override a synced id', () {
    const syncedA = ModelInfo(id: 'a', name: 'A', contextWindow: 131072);
    const syncedB = ModelInfo(id: 'b', name: 'B', contextWindow: 131072);
    const manualA = ModelInfo(
      id: 'a',
      name: 'A manual',
      contextWindow: 1000000,
      vision: true,
      source: 'manual',
    );
    const manualC = ModelInfo(
      id: 'c',
      name: 'C',
      contextWindow: 262144,
      source: 'manual',
    );
    const largerB = ModelInfo(id: 'b', name: 'B', contextWindow: 200000);

    final merged = mergeSyncedModels(
      synced: const [syncedA, syncedB],
      current: const [manualA, largerB, manualC],
    );

    expect(merged.map((m) => m.id), ['a', 'b', 'c']);
    expect(merged[0].name, 'A manual');
    expect(merged[0].source, 'manual');
    expect(merged[1].contextWindow, 200000);
    expect(merged[2].source, 'manual');
  });
}
