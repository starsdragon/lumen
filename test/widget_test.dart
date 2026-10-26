import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ui/markdown/markdown_view.dart';

void main() {
  test('preprocessMath converts inline and display math without touching code', () {
    const source = '''
行内公式 \$E = mc^2\$ 会被转换。

```dart
final price = '\$5';
```

\$\$
\\text{清晰度} = \\frac{a}{b}
\$\$
''';
    final prepared = preprocessMath(source);
    expect(prepared.contains('`lumen-math:'), isTrue);
    expect(prepared.contains('```lumen-math-display'), isTrue);
    expect(prepared.contains("final price = '\$5';"), isTrue);
  });
}
