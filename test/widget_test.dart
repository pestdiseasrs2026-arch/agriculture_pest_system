import 'package:agriculture_pest_system/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agriculture_pest_system/app/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agriculture_pest_system/main.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';

void main() {
  test('application themes enforce accessible interaction defaults', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.useMaterial3, isTrue);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.extension<AppSemanticColors>(), isNotNull);
      expect(
        theme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Tests can continue with the UI fallback path when Firebase is unavailable.
    }
  });

  testWidgets('app shows the authentication welcome screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(home: WelcomeScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agriculture Pest System'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets(
    'authentication gate initializes outside inherited dependencies',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthGate())),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('welcome screen highlights premium agriculture access', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(home: WelcomeScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Smart farming access'), findsOneWidget);
  });

  testWidgets('registration form exposes role and account status fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(home: WelcomeScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Account status'), findsOneWidget);
  });

  testWidgets('farmer dashboard shows core management actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Farmer Dashboard'), findsOneWidget);
    expect(find.text('Farm Profile'), findsOneWidget);
    expect(find.text('Crop Records'), findsWidgets);
  });

  testWidgets('dashboard header confirms logout', (tester) async {
    var loggedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
          onLogout: () async => loggedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
  });

  testWidgets('farm profile screen shows the farm creation form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmProfileScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Farm Profile'), findsOneWidget);
    expect(find.text('Farm name'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes disease detection workflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disease & Pest Detection'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes advisory workflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recommendations & Advice'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes knowledge base workflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Knowledge Base'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes report and notification modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reports & Exports'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes analytics and administration modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Analytics Dashboard'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes ai and security modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI Model Management'), findsOneWidget);
    expect(find.text('Security & Backup'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes soil and fertilizer modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soil Testing'), findsOneWidget);
    expect(find.text('Fertilizer Inventory'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes gis mapping module', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GIS Mapping'), findsOneWidget);
  });

  testWidgets('farmer dashboard exposes iot sensor integration module', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FarmerDashboardScreen(
          user: const UserProfile(
            uid: 'demo-user',
            fullName: 'Demo Farmer',
            email: 'farmer@example.com',
            phone: '',
            location: '',
            profileImage: '',
            authProvider: 'email',
            role: UserRole.farmer,
            accountStatus: AccountStatus.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('IoT Sensor Integration'), findsOneWidget);
  });

  test('generated Firebase options are treated as valid', () {
    expect(
      hasValidFirebaseConfiguration(DefaultFirebaseOptions.currentPlatform),
      isTrue,
    );
  });
}
