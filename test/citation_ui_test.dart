import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/ui/chat/message_view.dart';

void main() {
  testWidgets('citation pill opens the sources sheet', (tester) async {
    final message = ChatMessage.assistant(
      'conv',
      providerId: 'demo',
      modelId: 'demo',
      modelLabel: '演示模式',
    )
      ..text = '这是回答。'
      ..finishReason = 'stop'
      ..citations = const [
        Citation(
          title: '示例来源一',
          url: 'https://example.com/one',
          snippet: '来源一的摘要',
          index: 1,
          publishedAt: '2026-09-02T00:00:00Z',
        ),
        Citation(
          title: '示例来源二',
          url: 'https://example.com/two',
          snippet: '来源二的摘要',
          index: 2,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLumenTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(child: ChatMessageView(message: message)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 个网页'), findsOneWidget);
    await tester.tap(find.text('2 个网页'));
    await tester.pumpAndSettle();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('示例来源一'), findsOneWidget);
  });
}
