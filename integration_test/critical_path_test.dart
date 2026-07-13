import 'package:agriculture_pest_system/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can enter account creation from the launch screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(home: WelcomeScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agriculture Pest System'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Account role'), findsOneWidget);
  });
}
