import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme.dart';
import 'package:lumen/ui/settings/system_prompt_screen.dart';

void main() {
  testWidgets('system prompt editor keeps actions above the keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLumenTheme(brightness: Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 500),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: const SystemPromptScreen(initial: '测试提示词'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
