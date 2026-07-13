import 'package:agriculture_pest_system/core/accessibility/accessible_app.dart';
import 'package:agriculture_pest_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large text remains enabled without startup exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Agriculture Pest System'), findsOneWidget);
    final context = tester.element(find.byType(WelcomeScreen));
    expect(MediaQuery.textScalerOf(context).scale(16), 32);
  });

  testWidgets('reduced-motion preferences produce zero durations', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: AccessibleApp(
            child: Builder(
              builder: (context) {
                captured = context;
                return const Placeholder();
              },
            ),
          ),
        ),
      ),
    );

    expect(captured.reduceMotion, isTrue);
    expect(
      captured.motionDuration(const Duration(milliseconds: 300)),
      Duration.zero,
    );
  });
}
