import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_yi/app/app.dart';
import 'package:uni_yi/app/bootstrap/app_bootstrap.dart';

void main() {
  testWidgets('renders the app shell in testing mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bootstrap = await AppBootstrap.testing();

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrap.overrides.cast(),
        child: const UniYiApp(),
      ),
    );
    await tester.pumpAndSettle();

    final loginButton = find.text('登录');
    if (loginButton.evaluate().isNotEmpty) {
      await tester.tap(loginButton);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    expect(find.text('常用入口'), findsOneWidget);
    expect(find.text('总览'), findsAtLeastNWidgets(1));
    expect(find.text('课表'), findsAtLeastNWidgets(1));
    expect(find.text('通知'), findsAtLeastNWidgets(1));
    expect(find.text('设置'), findsAtLeastNWidgets(1));
  });
}
