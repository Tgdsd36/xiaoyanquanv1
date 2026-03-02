import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiaoyanquan/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: XiaoYanQuanApp()),
    );
    await tester.pumpAndSettle();
    // 基本验证 App 能正常启动（未登录时显示登录页）
    expect(find.text('小颜圈'), findsOneWidget);
  });
}
