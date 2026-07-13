import 'dart:async';

import 'package:agriculture_pest_system/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:agriculture_pest_system/app/theme/app_theme.dart';
import 'package:agriculture_pest_system/app/providers/theme_provider.dart';
import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/core/accessibility/accessible_app.dart';
import 'package:agriculture_pest_system/core/config/feature_flags.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';
import 'package:agriculture_pest_system/features/dashboard/domain/dashboard_metric.dart';
import 'package:agriculture_pest_system/features/dashboard/providers/dashboard_providers.dart';
import 'package:agriculture_pest_system/features/ai_detection/presentation/detection_workspace.dart';
import 'package:agriculture_pest_system/features/operations/presentation/operation_panels.dart';
import 'package:agriculture_pest_system/features/insights/presentation/insight_workspaces.dart';
import 'package:agriculture_pest_system/features/privacy/presentation/privacy_account_screen.dart';
import 'package:agriculture_pest_system/core/providers/repository_providers.dart';
import 'package:agriculture_pest_system/core/repositories/feature_repositories.dart';

OperationsRepository operationsOf(BuildContext context) =>
    ProviderScope.containerOf(context).read(operationsRepositoryProvider);

bool hasValidFirebaseConfiguration(FirebaseOptions options) {
  final values = <String?>[
    options.apiKey,
    options.appId,
    options.messagingSenderId,
    options.projectId,
    options.storageBucket,
  ];

  return values.every((value) => value != null && value.isNotEmpty) &&
      !values.any((value) => value!.contains('YOUR_'));
}

Future<void> legacyApplicationMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Continue running the UI even when Firebase is unavailable in tests or local preview builds.
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  final Widget? home;
  const MyApp({super.key, this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Agriculture Pest System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) {
        final flags = FeatureFlags.instance;
        if (flags.maintenanceMode) {
          return AccessibleApp(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.engineering_outlined, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          'Scheduled maintenance',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          flags.maintenanceMessage,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return AccessibleApp(child: child!);
      },
      home: home ?? const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  FirebaseAuth? _auth;
  AuthProfileRepository? _authRepository;
  StreamSubscription<User?>? _authSubscription;
  UserProfile? _currentUser;
  bool _isLoading = false;
  bool _firebaseReady = false;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    try {
      final options = DefaultFirebaseOptions.currentPlatform;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }

      if (Firebase.apps.isNotEmpty && hasValidFirebaseConfiguration(options)) {
        if (!mounted) return;
        _authRepository ??= ProviderScope.containerOf(
          context,
          listen: false,
        ).read(authProfileRepositoryProvider);
        _auth = _authRepository!.auth;
        _googleSignIn = GoogleSignIn.instance;
        _firebaseReady = true;

        _authSubscription = _auth!.authStateChanges().listen((user) async {
          if (!mounted) return;
          if (user == null) {
            setState(() {
              _currentUser = null;
              _isLoading = false;
            });
            return;
          }
          await _loadProfileFor(user);
        });
      } else {
        _firebaseReady = false;
      }
    } catch (_) {
      _firebaseReady = false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  UserProfile _fallbackProfileFor(User user) {
    final displayName = user.displayName?.trim();
    return UserProfile(
      uid: user.uid,
      fullName: displayName != null && displayName.isNotEmpty
          ? displayName
          : 'Farmer',
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      location: '',
      profileImage: user.photoURL ?? '',
      authProvider: user.providerData.isNotEmpty
          ? user.providerData.first.providerId
          : 'email',
      role: UserRole.farmer,
      accountStatus: AccountStatus.active,
    );
  }

  Future<UserProfile> _loadProfileFor(User user) async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final fallbackProfile = _fallbackProfileFor(user);

    if (!_firebaseReady || _authRepository == null) {
      if (mounted) {
        setState(() {
          _currentUser = fallbackProfile;
          _isLoading = false;
        });
      }
      return fallbackProfile;
    }

    try {
      final storedProfile = await _authRepository!
          .profile(user.uid)
          .timeout(const Duration(seconds: 15));
      final profile = storedProfile ?? fallbackProfile;

      if (storedProfile == null) {
        try {
          await _authRepository!
              .save(profile)
              .timeout(const Duration(seconds: 15));
        } catch (error, stackTrace) {
          debugPrint('Unable to create Firestore profile: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      if (mounted) {
        setState(() {
          _currentUser = profile;
          _isLoading = false;
        });
      }
      return profile;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firestore profile error: ${error.code} - ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Firestore profile request timed out: $error');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Unexpected profile-loading error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (mounted) {
      setState(() {
        _currentUser = fallbackProfile;
        _isLoading = false;
      });
    }
    return fallbackProfile;
  }

  Future<void> _registerUser(UserProfile profile, String password) async {
    if (_isLoading) return;
    if (!_firebaseReady || _auth == null) {
      throw FirebaseAuthException(
        code: 'firebase-not-ready',
        message: 'Firebase Authentication is not ready.',
      );
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final result = await _auth!.createUserWithEmailAndPassword(
        email: profile.email.trim().toLowerCase(),
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-returned',
          message: 'Firebase did not return the new user.',
        );
      }

      await user.updateDisplayName(profile.fullName);

      final savedProfile = profile.copyWith(
        uid: user.uid,
        email: user.email ?? profile.email.trim().toLowerCase(),
        authProvider: 'email',
        profileImage: '',
      );

      if (_authRepository != null) {
        try {
          await _authRepository!
              .save(savedProfile)
              .timeout(const Duration(seconds: 15));
        } catch (error, stackTrace) {
          debugPrint(
            'Profile saved locally because Firestore is unavailable: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentUser = savedProfile;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  Future<void> _loginUser(String email, String password) async {
    if (_isLoading) return;
    if (!_firebaseReady || _auth == null) {
      throw FirebaseAuthException(
        code: 'firebase-not-ready',
        message: 'Firebase Authentication is not ready.',
      );
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final result = await _auth!.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-returned',
          message: 'Firebase did not return a signed-in user.',
        );
      }

      await _loadProfileFor(user);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    if (!_firebaseReady || _auth == null) {
      throw FirebaseAuthException(
        code: 'firebase-not-ready',
        message: 'Firebase Authentication is not ready.',
      );
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      await _googleSignIn.initialize();
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final authResult = await _auth!.signInWithCredential(credential);
      final firebaseUser = authResult.user;
      if (firebaseUser == null) {
        throw FirebaseAuthException(
          code: 'user-not-returned',
          message: 'Firebase did not return a Google user.',
        );
      }

      await _loadProfileFor(firebaseUser);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser != null) {
      return FarmerDashboardScreen(user: _currentUser!);
    }

    return const WelcomeScreen();
  }
}

class FarmerDashboardScreen extends StatefulWidget {
  final UserProfile user;

  const FarmerDashboardScreen({super.key, required this.user});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  bool get _darkMode => Theme.of(context).brightness == Brightness.dark;
  bool _navigationExpanded = false;
  int _selectedDestination = 0;

  void _toggleTheme() => ProviderScope.containerOf(context)
      .read(themeModeProvider.notifier)
      .toggle(MediaQuery.platformBrightnessOf(context));

  final List<_ModuleAction> _moduleActions = const [
    _ModuleAction(
      icon: Icons.agriculture,
      title: 'Farm Profile',
      subtitle: 'Farm location and identity',
      route: 'farm',
    ),
    _ModuleAction(
      icon: Icons.eco,
      title: 'Crop Records',
      subtitle: 'Register crops and growth events',
      route: 'crops',
    ),
    _ModuleAction(
      icon: Icons.bug_report,
      title: 'Disease & Pest Detection',
      subtitle: 'AI-powered crop health checks',
      route: 'detection',
    ),
    _ModuleAction(
      icon: Icons.tips_and_updates,
      title: 'Recommendations & Advice',
      subtitle: 'Treatment and prevention recommendations',
      route: 'recommendations',
    ),
    _ModuleAction(
      icon: Icons.library_books,
      title: 'Knowledge Base',
      subtitle: 'Crop and disease reference',
      route: 'knowledge',
    ),
    _ModuleAction(
      icon: Icons.picture_as_pdf,
      title: 'Reports & Exports',
      subtitle: 'Generate PDF and export reports',
      route: 'reports',
    ),
    _ModuleAction(
      icon: Icons.notifications_active,
      title: 'Notifications',
      subtitle: 'Alerts and reminders',
      route: 'notifications',
    ),
    _ModuleAction(
      icon: Icons.insights,
      title: 'Analytics Dashboard',
      subtitle: 'Performance, trends and insights',
      route: 'analytics',
    ),
    _ModuleAction(
      icon: Icons.admin_panel_settings,
      title: 'Administration',
      subtitle: 'User and operational administration',
      route: 'admin',
    ),
    _ModuleAction(
      icon: Icons.smart_toy,
      title: 'AI Model Management',
      subtitle: 'Model versions and coverage',
      route: 'ai',
    ),
    _ModuleAction(
      icon: Icons.security,
      title: 'Security & Backup',
      subtitle: 'Permissions, logging and control',
      route: 'security',
    ),
    _ModuleAction(
      icon: Icons.map,
      title: 'GIS Mapping',
      subtitle: 'Farm, disease and pest mapping',
      route: 'gis',
    ),
    _ModuleAction(
      icon: Icons.sensors,
      title: 'IoT Sensor Integration',
      subtitle: 'Live environmental sensor inputs',
      route: 'iot',
    ),
    _ModuleAction(
      icon: Icons.terrain,
      title: 'Soil Testing',
      subtitle: 'Soil analysis and test history',
      route: 'soil',
    ),
    _ModuleAction(
      icon: Icons.inventory_2,
      title: 'Fertilizer Inventory',
      subtitle: 'Stock and usage management',
      route: 'fertilizer',
    ),
  ];

  void _openModule(BuildContext context, String route) {
    switch (route) {
      case 'farm':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FarmProfileScreen(user: widget.user),
          ),
        );
        break;
      case 'crops':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CropRecordScreen(user: widget.user),
          ),
        );
        break;
      case 'detection':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetectionScreen(user: widget.user)),
        );
        break;
      case 'recommendations':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecommendationScreen(user: widget.user),
          ),
        );
        break;
      case 'knowledge':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => KnowledgeBaseScreen(user: widget.user),
          ),
        );
        break;
      case 'reports':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportsWorkspace(user: widget.user),
          ),
        );
        break;
      case 'notifications':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveNotificationsWorkspace(user: widget.user),
          ),
        );
        break;
      case 'analytics':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnalyticsWorkspace(user: widget.user),
          ),
        );
        break;
      case 'admin':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminDashboardScreen(user: widget.user),
          ),
        );
        break;
      case 'ai':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AiModelManagementScreen(user: widget.user),
          ),
        );
        break;
      case 'security':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SecurityBackupScreen(user: widget.user),
          ),
        );
        break;
      case 'gis':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GISMappingScreen(user: widget.user),
          ),
        );
        break;
      case 'iot':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IoTSensorScreen(user: widget.user)),
        );
        break;
      case 'soil':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SoilTestingScreen(user: widget.user),
          ),
        );
        break;
      case 'fertilizer':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FertilizerInventoryScreen(user: widget.user),
          ),
        );
        break;
      case 'privacy':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivacyAccountScreen(user: widget.user),
          ),
        );
        break;
    }
  }

  List<_NavItem> get _navItems {
    final items = <_NavItem>[
      const _NavItem(Icons.dashboard_outlined, 'Dashboard', 'dashboard'),
      const _NavItem(Icons.bug_report_outlined, 'AI Detection', 'detection'),
      const _NavItem(Icons.agriculture_outlined, 'Farms', 'farm'),
      const _NavItem(Icons.eco_outlined, 'Crops', 'crops'),
      const _NavItem(
        Icons.tips_and_updates_outlined,
        'Recommendations',
        'recommendations',
      ),
      const _NavItem(Icons.terrain_outlined, 'Soil Testing', 'soil'),
      const _NavItem(
        Icons.inventory_2_outlined,
        'Fertilizer Inventory',
        'fertilizer',
      ),
      const _NavItem(Icons.map_outlined, 'GIS Map', 'gis'),
      const _NavItem(Icons.sensors_outlined, 'IoT Sensors', 'iot'),
      const _NavItem(Icons.history_outlined, 'Detection History', 'detection'),
      const _NavItem(Icons.description_outlined, 'Reports', 'reports'),
      const _NavItem(
        Icons.notifications_outlined,
        'Notifications',
        'notifications',
      ),
      const _NavItem(Icons.analytics_outlined, 'Analytics', 'analytics'),
      const _NavItem(
        Icons.privacy_tip_outlined,
        'Privacy & Account',
        'privacy',
      ),
    ];
    if (widget.user.role == UserRole.admin) {
      items.addAll(const [
        _NavItem(Icons.people_alt_outlined, 'User Management', 'admin'),
        _NavItem(Icons.smart_toy_outlined, 'AI Models', 'ai'),
        _NavItem(Icons.security_outlined, 'Security & Backup', 'security'),
      ]);
    }
    return items;
  }

  void _selectDestination(BuildContext context, int index) {
    final item = _navItems[index];
    setState(() => _selectedDestination = index);
    if (item.route != 'dashboard') _openModule(context, item.route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1024;
    final metricColumns = width >= 1440
        ? 4
        : width >= 720
        ? 2
        : 1;
    final dateLabel = DateFormat('EEE, MMM d • HH:mm').format(DateTime.now());

    final body = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade800,
                    Colors.green.shade600,
                    Colors.orange.shade700,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade100,
                    blurRadius: 24,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, ${widget.user.fullName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Monitor crop health, detect diseases early, and improve agricultural productivity using Artificial Intelligence.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  _openModule(context, 'detection'),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Run AI Detection'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.green.shade800,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openModule(context, 'analytics'),
                              icon: const Icon(Icons.insights_outlined),
                              label: const Text('View Analytics'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.terrain, color: Colors.white, size: 34),
                        SizedBox(height: 8),
                        Text(
                          'Digital Farming',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Operational intelligence overview',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.schedule_outlined, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text(dateLabel, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: metricColumns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.2,
              children: DashboardMetricType.values
                  .map((type) => _LiveMetricCard(type: type))
                  .toList(),
            ),
            const SizedBox(height: 20),
            _PanelCard(
              title: 'Core modules',
              subtitle: 'Navigate the full agriculture intelligence workspace.',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _moduleActions
                    .map(
                      (item) => GestureDetector(
                        onTap: () => _openModule(context, item.route),
                        child: _DashboardCard(
                          icon: item.icon,
                          title: item.title,
                          subtitle: item.subtitle,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PanelCard(
                    title: 'AI Detection Studio',
                    subtitle:
                        'Upload, preview and review AI predictions in one place.',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Upload Image'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Capture Image'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.green.shade100),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  size: 48,
                                  color: Colors.green,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Preview and model output will appear here',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: 0.78,
                            minHeight: 9,
                            backgroundColor: Colors.green.shade100,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            Expanded(child: Text('Processing AI model')),
                            SizedBox(width: 8),
                            Text('78% complete'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _PanelCard(
                    title: 'Detection Results',
                    subtitle:
                        'Confidence, severity, treatment and prevention guidance.',
                    child: Column(
                      children: [
                        const _ResultTile(
                          crop: 'Maize',
                          disease: 'Leaf Blight',
                          confidence: 0.94,
                          severity: 'High',
                          treatment: 'Apply fungicide and increase airflow',
                        ),
                        const SizedBox(height: 10),
                        const _ResultTile(
                          crop: 'Tomato',
                          disease: 'Early Blight',
                          confidence: 0.89,
                          severity: 'Medium',
                          treatment:
                              'Remove affected leaves and monitor humidity',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PanelCard(
                    title: 'GIS Monitoring',
                    subtitle: 'Track farms, hotspots and sampling areas.',
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          children: const [
                            Chip(label: Text('Farms')),
                            Chip(label: Text('Disease Hotspots')),
                            Chip(label: Text('Pest Hotspots')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade50,
                                Colors.blue.shade50,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.map_rounded,
                                  size: 42,
                                  color: Colors.green,
                                ),
                                SizedBox(height: 8),
                                Text('Interactive monitoring view'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _PanelCard(
                    title: 'IoT Sensor Health',
                    subtitle:
                        'Real-time environmental values and device status.',
                    child: Column(
                      children: const [
                        _SensorLine(
                          icon: Icons.water_drop_outlined,
                          label: 'Soil Moisture',
                          value: '72%',
                          color: Colors.blue,
                        ),
                        _SensorLine(
                          icon: Icons.thermostat_outlined,
                          label: 'Soil Temperature',
                          value: '28°C',
                          color: Colors.orange,
                        ),
                        _SensorLine(
                          icon: Icons.air_outlined,
                          label: 'Air Humidity',
                          value: '64%',
                          color: Colors.indigo,
                        ),
                        _SensorLine(
                          icon: Icons.waves_outlined,
                          label: 'Rainfall',
                          value: '12 mm',
                          color: Colors.teal,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _PanelCard(
              title: 'Analytics Overview',
              subtitle:
                  'Professional charts for disease trends, pest distribution and crop health.',
              child: Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: const [
                              FlSpot(0, 2),
                              FlSpot(1, 3),
                              FlSpot(2, 2.4),
                              FlSpot(3, 3.5),
                              FlSpot(4, 3.2),
                              FlSpot(5, 4.3),
                            ],
                            isCurved: true,
                            color: Colors.green.shade700,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 34,
                        sections: [
                          PieChartSectionData(
                            value: 40,
                            color: Colors.green.shade700,
                            title: 'Healthy',
                          ),
                          PieChartSectionData(
                            value: 35,
                            color: Colors.orange.shade700,
                            title: 'Risk',
                          ),
                          PieChartSectionData(
                            value: 25,
                            color: Colors.blue.shade700,
                            title: 'Monitor',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PanelCard(
                    title: 'Recent Activity',
                    subtitle:
                        'Recent registrations, detections, tests and reports.',
                    child: Column(
                      children: const [
                        _ActivityItem(
                          title: 'New farmer registered',
                          subtitle: 'North District • 5 mins ago',
                        ),
                        _ActivityItem(
                          title: 'AI detection completed',
                          subtitle: 'Maize field • 12 mins ago',
                        ),
                        _ActivityItem(
                          title: 'Soil test submitted',
                          subtitle: 'Green Valley • 32 mins ago',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _PanelCard(
                    title: 'Alert Center',
                    subtitle: 'Alerts, reminders and system announcements.',
                    child: Column(
                      children: const [
                        _ActivityItem(
                          title: 'Disease alert',
                          subtitle: 'High priority • 2 farms affected',
                          color: Colors.red,
                        ),
                        _ActivityItem(
                          title: 'Weather alert',
                          subtitle: 'Heavy rain expected tomorrow',
                          color: Colors.orange,
                        ),
                        _ActivityItem(
                          title: 'Recommendation reminder',
                          subtitle: 'Apply treatment before noon',
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _PanelCard(
              title: 'Operations',
              subtitle:
                  'Quick actions for reports, exports, settings and support.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openModule(context, 'reports'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Generate PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Export Excel'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print Report'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share Report'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.eco_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Agriculture Pest and Disease Detection System • Powered by Flutter + Firebase + Artificial Intelligence',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final navItems = _navItems;

    final navigationRail = NavigationRail(
      selectedIndex: _selectedDestination,
      extended: _navigationExpanded,
      minExtendedWidth: 248,
      onDestinationSelected: (index) => _selectDestination(context, index),
      labelType: _navigationExpanded
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.selected,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IconButton(
          tooltip: _navigationExpanded
              ? 'Collapse navigation'
              : 'Expand navigation',
          onPressed: () =>
              setState(() => _navigationExpanded = !_navigationExpanded),
          icon: Icon(_navigationExpanded ? Icons.menu_open : Icons.menu),
        ),
      ),
      destinations: navItems
          .map(
            (item) => NavigationRailDestination(
              icon: Tooltip(message: item.label, child: Icon(item.icon)),
              label: Text(item.label),
            ),
          )
          .toList(),
    );

    final drawer = Drawer(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Text(
              'AgriAI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ...navItems.map(
            (item) => ListTile(
              leading: Icon(item.icon, color: Colors.green.shade700),
              title: Text(item.label),
              selected: _selectedDestination == navItems.indexOf(item),
              onTap: () {
                Navigator.pop(context);
                _selectDestination(context, navItems.indexOf(item));
              },
            ),
          ),
        ],
      ),
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              child: navigationRail,
            ),
            Expanded(
              child: Column(
                children: [
                  _DashboardTopBar(
                    user: widget.user,
                    darkMode: _darkMode,
                    onThemeChanged: _toggleTheme,
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Farmer Dashboard'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
          IconButton(
            onPressed: _toggleTheme,
            icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      drawer: drawer,
      body: body,
    );
  }
}

class _ModuleAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _ModuleAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  const _NavItem(this.icon, this.label, this.route);
}

class _DashboardTopBar extends StatelessWidget {
  final UserProfile user;
  final bool darkMode;
  final VoidCallback onThemeChanged;

  const _DashboardTopBar({
    required this.user,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            Icon(Icons.eco_rounded, color: colors.primary, size: 28),
            const SizedBox(width: 12),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AgriAI Intelligence',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Dashboard / Overview', style: TextStyle(fontSize: 12)),
              ],
            ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search farms, crops, detections…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Online • synchronized',
              child: Chip(
                avatar: const Icon(Icons.cloud_done_outlined, size: 18),
                label: const Text('Synced'),
                side: BorderSide.none,
              ),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {},
              icon: Badge(
                label: const Text('3'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            IconButton(
              tooltip: darkMode ? 'Use light theme' : 'Use dark theme',
              onPressed: onThemeChanged,
              icon: Icon(
                darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Text(
                user.fullName.isEmpty ? 'U' : user.fullName[0].toUpperCase(),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  user.role.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMetricCard extends ConsumerWidget {
  final DashboardMetricType type;

  const _LiveMetricCard({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Firebase.apps.isEmpty) {
      return _MetricCard(
        icon: type.icon,
        title: type.label,
        value: '—',
        trend: 'Offline',
        badge: 'Unavailable',
        color: type.color,
      );
    }
    final metric = ref.watch(dashboardMetricProvider(type));
    return metric.when(
      data: (data) {
        final count = data.value;
        return _MetricCard(
          icon: type.icon,
          title: type.label,
          value: NumberFormat.decimalPattern().format(count),
          trend: count == 0 ? 'No records yet' : 'Updated now',
          badge: count == 0 ? 'Empty' : 'Live',
          color: type.color,
        );
      },
      loading: () => _MetricCard(
        icon: type.icon,
        title: type.label,
        value: '…',
        trend: 'Syncing',
        badge: 'Loading',
        color: type.color,
      ),
      error: (error, _) => _MetricCard(
        icon: type.icon,
        title: type.label,
        value: '—',
        trend: error is AppException ? error.message : 'Unable to load',
        badge: 'Error',
        color: type.color,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String trend;
  final String badge;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.trend,
    required this.badge,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            trend,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String crop;
  final String disease;
  final double confidence;
  final String severity;
  final String treatment;

  const _ResultTile({
    required this.crop,
    required this.disease,
    required this.confidence,
    required this.severity,
    required this.treatment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  crop,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  severity,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(disease, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: confidence,
              color: Colors.green.shade700,
              backgroundColor: Colors.green.shade100,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence ${((confidence * 100).round())}% • $treatment',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SensorLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SensorLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _ActivityItem({
    required this.title,
    required this.subtitle,
    this.color = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnalyticsDashboardScreen extends StatefulWidget {
  final UserProfile user;

  const AnalyticsDashboardScreen({super.key, required this.user});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>> get _detectionsStream {
    if (!Firebase.apps.isNotEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return operationsOf(context).watch('detections', ownerId: widget.user.uid);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _cropsStream {
    if (!Firebase.apps.isNotEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return operationsOf(context).watch('cropRecords', ownerId: widget.user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Dashboard')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _detectionsStream,
        builder: (context, detectionSnapshot) {
          final detections = detectionSnapshot.hasData
              ? detectionSnapshot.data!.docs
                    .map((doc) => DetectionRecord.fromMap(doc.data()))
                    .toList()
              : <DetectionRecord>[];

          final totalDetections = detections.length;
          final highSeverityCount = detections.where((entry) {
            final severity = entry.severity.toLowerCase();
            return severity == 'high' || severity == 'moderate';
          }).length;
          final averageConfidence = detections.isEmpty
              ? 0.0
              : detections.fold<double>(0, (total, entry) {
                      final value =
                          double.tryParse(entry.confidenceScore) ?? 0.0;
                      return total + value;
                    }) /
                    detections.length;
          final cropHealth = (averageConfidence * 100).round();
          final pestSignals = detections.where((entry) {
            final disease = entry.diseaseName.toLowerCase();
            return disease.contains('pest') ||
                disease.contains('blight') ||
                disease.contains('spot');
          }).length;

          final chartSpots = <FlSpot>[];
          for (var index = 0; index < detections.length && index < 6; index++) {
            final confidence =
                double.tryParse(detections[index].confidenceScore) ?? 0.0;
            chartSpots.add(FlSpot(index.toDouble(), confidence * 4));
          }

          if (chartSpots.isEmpty) {
            chartSpots.addAll(const [
              FlSpot(0, 2),
              FlSpot(1, 3.2),
              FlSpot(2, 2.8),
              FlSpot(3, 4.1),
              FlSpot(4, 3.4),
            ]);
          }

          final stats = [
            {'label': 'Detections', 'value': '$totalDetections'},
            {'label': 'Active Issues', 'value': '$highSeverityCount'},
            {'label': 'Pest Signals', 'value': '$pestSignals'},
            {'label': 'Crop Health', 'value': '$cropHealth%'},
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live detection activity from your farm records and AI assessments.',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  'Updated ${DateFormat('HH:mm').format(DateTime.now())}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.7,
                  physics: const NeverScrollableScrollPhysics(),
                  children: stats
                      .map(
                        (item) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['value'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(item['label'] ?? ''),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Disease trends',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: true,
                              color: Colors.green.shade700,
                              barWidth: 3,
                            ),
                          ],
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Live activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _cropsStream,
                  builder: (context, cropSnapshot) {
                    final crops = cropSnapshot.hasData
                        ? cropSnapshot.data!.docs
                              .map((doc) => CropRecord.fromMap(doc.data()))
                              .toList()
                        : <CropRecord>[];

                    final activities = [
                      ...detections
                          .take(3)
                          .map(
                            (entry) => ListTile(
                              leading: const Icon(Icons.bug_report_outlined),
                              title: Text(
                                entry.diseaseName.isEmpty
                                    ? 'Detection update'
                                    : entry.diseaseName,
                              ),
                              subtitle: Text(
                                '${entry.cropType} • ${entry.severity} severity',
                              ),
                            ),
                          ),
                      ...crops
                          .take(2)
                          .map(
                            (crop) => ListTile(
                              leading: const Icon(Icons.eco_outlined),
                              title: Text(crop.cropName),
                              subtitle: Text(
                                'Planting ${crop.plantingDate} • Harvest ${crop.harvestDate}',
                              ),
                            ),
                          ),
                    ];

                    return Card(
                      child: Column(
                        children: activities.isEmpty
                            ? [
                                const ListTile(
                                  leading: Icon(Icons.timeline),
                                  title: Text('No live activity yet'),
                                  subtitle: Text(
                                    'New detections and crop updates will appear here instantly.',
                                  ),
                                ),
                              ]
                            : activities,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  final UserProfile user;

  const AdminDashboardScreen({super.key, required this.user});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final List<String> _sections = [
    'Manage Users',
    'Manage Crops',
    'Manage Diseases',
    'Manage Pests',
    'Manage Recommendations',
    'View System Reports',
    'Monitor Activities',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          final section = _sections[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text(section),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await operationsOf(
                  context,
                ).document('admins', widget.user.uid).set({
                  'name': widget.user.fullName,
                  'email': widget.user.email,
                  'section': section,
                  'timestamp': DateTime.now().toIso8601String(),
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$section selected for management')),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class AiModelManagementScreen extends StatefulWidget {
  final UserProfile user;

  const AiModelManagementScreen({super.key, required this.user});

  @override
  State<AiModelManagementScreen> createState() =>
      _AiModelManagementScreenState();
}

class _AiModelManagementScreenState extends State<AiModelManagementScreen> {
  final List<Map<String, String>> _models = [
    {
      'version': 'v2.1',
      'accuracy': '92%',
      'crops': 'Tomato, Maize',
      'diseases': 'Late Blight, Leaf Blight',
      'update': 'Updated 2h ago',
    },
    {
      'version': 'v2.0',
      'accuracy': '88%',
      'crops': 'Rice, Potato',
      'diseases': 'Rice Blast, Early Blight',
      'update': 'Updated 1 day ago',
    },
  ];

  Future<void> _registerModel(Map<String, String> model) async {
    await operationsOf(context).add('ai_models', {
      'version': model['version'],
      'accuracy': model['accuracy'],
      'crops': model['crops'],
      'diseases': model['diseases'],
      'update': model['update'],
      'owner': widget.user.uid,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Model ${model['version']} registered')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Model Management')),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _models.length,
        itemBuilder: (context, index) {
          final model = _models[index];
          return Card(
            child: ListTile(
              title: Text('Model ${model['version']}'),
              subtitle: Text(
                'Accuracy: ${model['accuracy']} • Crops: ${model['crops']} • Diseases: ${model['diseases']}',
              ),
              trailing: Text(model['update'] ?? ''),
              onTap: () => _registerModel(model),
            ),
          );
        },
      ),
    );
  }
}

class SecurityBackupScreen extends StatefulWidget {
  final UserProfile user;

  const SecurityBackupScreen({super.key, required this.user});

  @override
  State<SecurityBackupScreen> createState() => _SecurityBackupScreenState();
}

class _SecurityBackupScreenState extends State<SecurityBackupScreen> {
  final List<Map<String, String>> _securityItems = [
    {
      'title': 'Database security rules',
      'detail': 'Firestore rules enforce farmer and admin access boundaries.',
    },
    {
      'title': 'User permissions',
      'detail':
          'Role-based access is enforced for farmers, officers, and admins.',
    },
    {
      'title': 'Audit logs',
      'detail':
          'System activity is logged for admin review and incident tracking.',
    },
    {
      'title': 'Backup management',
      'detail':
          'Scheduled backups are configured for detection and advisory records.',
    },
  ];

  Future<void> _logSecurityAction(String action) async {
    await operationsOf(context).add('systemLogs', {
      'user': widget.user.fullName,
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$action recorded')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security & Backup')),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _securityItems.length,
        itemBuilder: (context, index) {
          final item = _securityItems[index];
          return Card(
            child: ListTile(
              title: Text(item['title'] ?? ''),
              subtitle: Text(item['detail'] ?? ''),
              trailing: const Icon(Icons.lock_outline),
              onTap: () => _logSecurityAction(item['title'] ?? ''),
            ),
          );
        },
      ),
    );
  }
}

class SoilTestingScreen extends StatefulWidget {
  final UserProfile user;

  const SoilTestingScreen({super.key, required this.user});

  @override
  State<SoilTestingScreen> createState() => _SoilTestingScreenState();
}

class _SoilTestingScreenState extends State<SoilTestingScreen> {
  final _sampleController = TextEditingController();
  final _phController = TextEditingController();
  final _nitrogenController = TextEditingController();
  final _phosphorusController = TextEditingController();
  final _potassiumController = TextEditingController();
  final _organicMatterController = TextEditingController();
  final _moistureController = TextEditingController();
  final _statusController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _sampleController.dispose();
    _phController.dispose();
    _nitrogenController.dispose();
    _phosphorusController.dispose();
    _potassiumController.dispose();
    _organicMatterController.dispose();
    _moistureController.dispose();
    _statusController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveSoilData() async {
    final ph = double.tryParse(_phController.text.trim());
    final nitrogen = double.tryParse(_nitrogenController.text.trim());
    final phosphorus = double.tryParse(_phosphorusController.text.trim());
    final potassium = double.tryParse(_potassiumController.text.trim());
    final organicMatter = double.tryParse(_organicMatterController.text.trim());
    final moisture = double.tryParse(_moistureController.text.trim());
    if (_sampleController.text.trim().isEmpty ||
        ph == null ||
        ph < 0 ||
        ph > 14 ||
        nitrogen == null ||
        nitrogen < 0 ||
        phosphorus == null ||
        phosphorus < 0 ||
        potassium == null ||
        potassium < 0 ||
        organicMatter == null ||
        organicMatter < 0 ||
        organicMatter > 100 ||
        moisture == null ||
        moisture < 0 ||
        moisture > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a sample name and valid numeric values (pH 0–14; percentages 0–100).',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        'farmerId': widget.user.uid,
        'sampleName': _sampleController.text.trim(),
        'sampleId': DateTime.now().microsecondsSinceEpoch.toString(),
        'ph': ph,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'organicMatter': organicMatter,
        'moisture': moisture,
        'status': _statusController.text.trim(),
        'notes': _notesController.text.trim(),
        'createdAt': DateTime.now().toIso8601String(),
        'recommendation': ph < 5.5
            ? 'Apply agricultural lime based on laboratory guidance.'
            : ph > 7.5
            ? 'Use acidifying organic amendments and monitor pH.'
            : 'Maintain balanced nutrients and organic matter.',
      };
      await operationsOf(context).saveSoilAnalysis(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soil analysis saved successfully')),
      );
      _sampleController.clear();
      _phController.clear();
      _nitrogenController.clear();
      _phosphorusController.clear();
      _potassiumController.clear();
      _organicMatterController.clear();
      _moistureController.clear();
      _statusController.clear();
      _notesController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soil Testing')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Register soil samples and capture lab-ready results for better fertilizer advice.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sampleController,
              decoration: const InputDecoration(labelText: 'Sample name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phController,
              decoration: const InputDecoration(labelText: 'Soil pH'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nitrogenController,
              decoration: const InputDecoration(
                labelText: 'Nitrogen (N) level',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phosphorusController,
              decoration: const InputDecoration(
                labelText: 'Phosphorus (P) level',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _potassiumController,
              decoration: const InputDecoration(
                labelText: 'Potassium (K) level',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _organicMatterController,
              decoration: const InputDecoration(labelText: 'Organic matter'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _moistureController,
              decoration: const InputDecoration(labelText: 'Soil moisture'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _statusController,
              decoration: const InputDecoration(labelText: 'Fertility status'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveSoilData,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save soil analysis'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Soil health history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SoilHistoryPanel(uid: widget.user.uid),
          ],
        ),
      ),
    );
  }
}

class FertilizerInventoryScreen extends StatefulWidget {
  final UserProfile user;

  const FertilizerInventoryScreen({super.key, required this.user});

  @override
  State<FertilizerInventoryScreen> createState() =>
      _FertilizerInventoryScreenState();
}

class _FertilizerInventoryScreenState extends State<FertilizerInventoryScreen> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _stockController = TextEditingController();
  final _supplierController = TextEditingController();
  final _usageController = TextEditingController();
  final _reorderController = TextEditingController(text: '10');
  final _expiryController = TextEditingController();
  String _transactionType = 'stock_in';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _stockController.dispose();
    _supplierController.dispose();
    _usageController.dispose();
    _reorderController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _saveInventory() async {
    final quantity = double.tryParse(_stockController.text.trim());
    final reorder = double.tryParse(_reorderController.text.trim());
    final name = _nameController.text.trim();
    final expiry = DateTime.tryParse(_expiryController.text.trim());
    if (name.isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        reorder == null ||
        reorder < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a fertilizer name, positive quantity, and valid reorder level.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final itemId = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await operationsOf(context).recordInventoryTransaction(
        uid: widget.user.uid,
        itemId: itemId,
        name: name,
        quantity: quantity,
        reorderLevel: reorder,
        transactionType: _transactionType,
        expiryDate: expiry,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fertilizer entry saved successfully')),
      );
      _nameController.clear();
      _categoryController.clear();
      _stockController.clear();
      _supplierController.clear();
      _usageController.clear();
      _expiryController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fertilizer Inventory')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Track stock, suppliers, and fertilizer usage records for each operation.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Fertilizer name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stockController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Transaction quantity',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _transactionType,
              decoration: const InputDecoration(labelText: 'Transaction'),
              items: const [
                DropdownMenuItem(value: 'stock_in', child: Text('Stock in')),
                DropdownMenuItem(value: 'stock_out', child: Text('Stock out')),
              ],
              onChanged: (value) =>
                  setState(() => _transactionType = value ?? 'stock_in'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reorderController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Reorder level'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expiryController,
              decoration: const InputDecoration(
                labelText: 'Expiry date (YYYY-MM-DD)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplierController,
              decoration: const InputDecoration(labelText: 'Supplier'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usageController,
              decoration: const InputDecoration(labelText: 'Usage record'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveInventory,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save fertilizer record'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Inventory history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FertilizerHistoryPanel(uid: widget.user.uid),
          ],
        ),
      ),
    );
  }
}

class IoTSensorScreen extends StatefulWidget {
  final UserProfile user;

  const IoTSensorScreen({super.key, required this.user});

  @override
  State<IoTSensorScreen> createState() => _IoTSensorScreenState();
}

class _IoTSensorScreenState extends State<IoTSensorScreen> {
  final _deviceNameController = TextEditingController();
  final _locationController = TextEditingController();
  final _soilMoistureController = TextEditingController();
  final _soilTemperatureController = TextEditingController();
  final _airTemperatureController = TextEditingController();
  final _airHumidityController = TextEditingController();
  final _soilPhController = TextEditingController();
  final _rainfallController = TextEditingController();
  final _lightController = TextEditingController();
  final _waterLevelController = TextEditingController();
  final _statusController = TextEditingController();
  final _alertController = TextEditingController();
  final _batteryController = TextEditingController();
  final _signalController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _deviceNameController.dispose();
    _locationController.dispose();
    _soilMoistureController.dispose();
    _soilTemperatureController.dispose();
    _airTemperatureController.dispose();
    _airHumidityController.dispose();
    _soilPhController.dispose();
    _rainfallController.dispose();
    _lightController.dispose();
    _waterLevelController.dispose();
    _statusController.dispose();
    _alertController.dispose();
    _batteryController.dispose();
    _signalController.dispose();
    super.dispose();
  }

  Future<void> _saveSensorReading() async {
    setState(() => _saving = true);
    try {
      final deviceName = _deviceNameController.text.trim();
      final location = _locationController.text.trim();
      final now = DateTime.now().toIso8601String();
      final sensorData = {
        'farmerId': widget.user.uid,
        'deviceName': deviceName.isEmpty ? 'Sensor Unit' : deviceName,
        'location': location.isEmpty ? 'Field A' : location,
        'soilMoisture': _soilMoistureController.text.trim(),
        'soilTemperature': _soilTemperatureController.text.trim(),
        'airTemperature': _airTemperatureController.text.trim(),
        'airHumidity': _airHumidityController.text.trim(),
        'soilPh': _soilPhController.text.trim(),
        'rainfall': _rainfallController.text.trim(),
        'lightIntensity': _lightController.text.trim(),
        'waterLevel': _waterLevelController.text.trim(),
        'battery': double.tryParse(_batteryController.text.trim()),
        'signalStrength': double.tryParse(_signalController.text.trim()),
        'status': _statusController.text.trim().isEmpty
            ? 'Online'
            : _statusController.text.trim(),
        'timestamp': now,
      };

      final operations = ProviderScope.containerOf(
        context,
      ).read(operationsRepositoryProvider);
      await operations.add('sensor_readings', sensorData);
      await operations.add('iot_devices', {
        'farmerId': widget.user.uid,
        'deviceName': deviceName.isEmpty ? 'Sensor Unit' : deviceName,
        'location': location.isEmpty ? 'Field A' : location,
        'status': _statusController.text.trim().isEmpty
            ? 'Online'
            : _statusController.text.trim(),
        'updatedAt': now,
      });
      await operations.add('weather_data', {
        'farmerId': widget.user.uid,
        'airTemperature': _airTemperatureController.text.trim(),
        'airHumidity': _airHumidityController.text.trim(),
        'rainfall': _rainfallController.text.trim(),
        'timestamp': now,
      });

      await operations.writeSensor(
        'sensor_readings/${widget.user.uid}',
        sensorData,
      );

      if (_alertController.text.trim().isNotEmpty) {
        await operations.add('sensor_alerts', {
          'farmerId': widget.user.uid,
          'message': _alertController.text.trim(),
          'timestamp': now,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor data uploaded successfully')),
      );
      _deviceNameController.clear();
      _locationController.clear();
      _soilMoistureController.clear();
      _soilTemperatureController.clear();
      _airTemperatureController.clear();
      _airHumidityController.clear();
      _soilPhController.clear();
      _rainfallController.clear();
      _lightController.clear();
      _waterLevelController.clear();
      _statusController.clear();
      _alertController.clear();
      _batteryController.clear();
      _signalController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IoT Sensor Integration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Collect live environmental sensor values and feed them into alerts and dashboards.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: 'Device name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Sensor location'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _soilMoistureController,
              decoration: const InputDecoration(labelText: 'Soil moisture (%)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _soilTemperatureController,
              decoration: const InputDecoration(
                labelText: 'Soil temperature (°C)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _airTemperatureController,
              decoration: const InputDecoration(
                labelText: 'Air temperature (°C)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _airHumidityController,
              decoration: const InputDecoration(labelText: 'Air humidity (%)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _soilPhController,
              decoration: const InputDecoration(labelText: 'Soil pH'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rainfallController,
              decoration: const InputDecoration(labelText: 'Rainfall (mm)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lightController,
              decoration: const InputDecoration(
                labelText: 'Light intensity (lux)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _waterLevelController,
              decoration: const InputDecoration(labelText: 'Water level'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _statusController,
              decoration: const InputDecoration(labelText: 'Sensor status'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batteryController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Battery level (%)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _signalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Signal strength (%)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _alertController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Sensor alert message',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveSensorReading,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save sensor snapshot'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Live farm sensor overview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SensorOverviewPanel(uid: widget.user.uid),
            const SizedBox(height: 8),
            const Text(
              'The app writes sensor readings to Firestore and Realtime Database so dashboards can stay updated in near real time.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class GISMappingScreen extends StatefulWidget {
  final UserProfile user;

  const GISMappingScreen({super.key, required this.user});

  @override
  State<GISMappingScreen> createState() => _GISMappingScreenState();
}

class _GISMappingScreenState extends State<GISMappingScreen> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedLayer = 'farm';
  bool _loading = true;
  bool _saving = false;
  LatLng _currentPosition = const LatLng(0.0, 0.0);
  final Set<Marker> _markers = <Marker>{};
  final Set<String> _visibleLayers = {'farm', 'disease', 'pest'};
  Map<String, dynamic>? _selectedMarker;
  String? _mapError;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is disabled.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
      await _loadMarkers();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMarkers() async {
    final collections = <String, String>{
      'farm_locations': 'Farm location',
      'disease_locations': 'Disease hotspot',
      'pest_locations': 'Pest hotspot',
    };
    final loadedMarkers = <Marker>{};
    for (final entry in collections.entries) {
      final layer = entry.key.split('_').first;
      if (!_visibleLayers.contains(layer)) continue;
      final documents = await operationsOf(
        context,
      ).getOwned(entry.key, widget.user.uid);
      for (final doc in documents) {
        final lat = doc['latitude'];
        final lng = doc['longitude'];
        if (lat is num && lng is num) {
          loadedMarkers.add(
            Marker(
              markerId: MarkerId('${entry.key}-${doc.id}'),
              position: LatLng(lat.toDouble(), lng.toDouble()),
              infoWindow: InfoWindow(
                title: doc['label']?.toString() ?? entry.value,
              ),
              onTap: () => setState(
                () => _selectedMarker = {...doc.data(), 'layer': layer},
              ),
            ),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _mapError = null;
      _markers
        ..clear()
        ..addAll(loadedMarkers);
    });
  }

  Future<void> _saveLocation() async {
    setState(() => _saving = true);
    final operations = ProviderScope.containerOf(
      context,
    ).read(operationsRepositoryProvider);
    try {
      final address = _addressController.text.trim();
      final label = _labelController.text.trim();
      final notes = _notesController.text.trim();
      var latitude = _currentPosition.latitude;
      var longitude = _currentPosition.longitude;

      if (address.isNotEmpty) {
        final locations = await locationFromAddress(address);
        if (locations.isNotEmpty) {
          latitude = locations.first.latitude;
          longitude = locations.first.longitude;
        }
      }

      final collectionName = switch (_selectedLayer) {
        'farm' => 'farm_locations',
        'disease' => 'disease_locations',
        'pest' => 'pest_locations',
        _ => 'farm_locations',
      };

      await operations.add(collectionName, {
        'farmerId': widget.user.uid,
        'label': label.isEmpty ? 'Mapped location' : label,
        'address': address,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'layer': _selectedLayer,
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location saved to the GIS map')),
      );
      _labelController.clear();
      _addressController.clear();
      _notesController.clear();
      await _loadMarkers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GIS Mapping')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Visualize farms, disease hotspots and pest pressure on an interactive map.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Map layers',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['farm', 'disease', 'pest'].map((layer) {
                        return FilterChip(
                          label: Text(layer),
                          selected: _visibleLayers.contains(layer),
                          onSelected: (selected) async {
                            setState(
                              () => selected
                                  ? _visibleLayers.add(layer)
                                  : _visibleLayers.remove(layer),
                            );
                            try {
                              await _loadMarkers();
                            } catch (error) {
                              if (mounted) setState(() => _mapError = '$error');
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLayer,
                      decoration: const InputDecoration(labelText: 'Layer'),
                      items: const [
                        DropdownMenuItem(
                          value: 'farm',
                          child: Text('Farm locations'),
                        ),
                        DropdownMenuItem(
                          value: 'disease',
                          child: Text('Disease locations'),
                        ),
                        DropdownMenuItem(
                          value: 'pest',
                          child: Text('Pest locations'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedLayer = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Location label',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address or place name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveLocation,
                            icon: const Icon(Icons.save_alt),
                            label: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save location'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _initializeLocation,
                            icon: const Icon(Icons.my_location),
                            label: const Text('Use GPS'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: _mapError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 40),
                          Text('Map unavailable: $_mapError'),
                          TextButton(
                            onPressed: _initializeLocation,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentPosition,
                        zoom: 5,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      markers: _markers,
                    ),
            ),
            if (_selectedMarker != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    _selectedMarker!['label']?.toString() ?? 'Location',
                  ),
                  subtitle: Text(
                    '${_selectedMarker!['layer']} • ${_selectedMarker!['address'] ?? ''}\n${_selectedMarker!['notes'] ?? ''}',
                  ),
                  trailing: IconButton(
                    onPressed: () => setState(() => _selectedMarker = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Regional analysis support',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the map to compare farm clusters, disease hotspots and pest pressure by region before planning interventions.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class FarmProfileScreen extends StatefulWidget {
  final UserProfile user;

  const FarmProfileScreen({super.key, required this.user});

  @override
  State<FarmProfileScreen> createState() => _FarmProfileScreenState();
}

class _FarmProfileScreenState extends State<FarmProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _sizeController = TextEditingController();
  final _cropsController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _sizeController.dispose();
    _cropsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final farm = FarmProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      farmerId: widget.user.uid,
      name: _nameController.text.trim(),
      location: _locationController.text.trim(),
      size: _sizeController.text.trim(),
      crops: _cropsController.text.trim(),
    );

    try {
      if (Firebase.apps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firestore is unavailable in this environment.'),
          ),
        );
        return;
      }

      await ProviderScope.containerOf(
        context,
      ).read(farmCropRepositoryProvider).addFarm(farm);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Farm profile saved to Firestore')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreReady = Firebase.apps.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Farm Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Farm name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a farm name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the farm location'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sizeController,
                decoration: const InputDecoration(labelText: 'Farm size'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cropsController,
                decoration: const InputDecoration(labelText: 'Main crops'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Save farm profile'),
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved farms',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: !firestoreReady
                    ? const Stream.empty()
                    : operationsOf(
                        context,
                      ).watch('farms', ownerId: widget.user.uid),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('No farms saved yet.');
                  }

                  final farms = snapshot.data!.docs
                      .map((doc) => FarmProfile.fromMap(doc.data(), id: doc.id))
                      .toList();

                  return Column(
                    children: farms
                        .map(
                          (farm) => Card(
                            child: ListTile(
                              title: Text(farm.name),
                              subtitle: Text('${farm.location} • ${farm.size}'),
                              trailing: Text(farm.crops),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CropRecordScreen extends StatefulWidget {
  final UserProfile user;

  const CropRecordScreen({super.key, required this.user});

  @override
  State<CropRecordScreen> createState() => _CropRecordScreenState();
}

class _CropRecordScreenState extends State<CropRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cropNameController = TextEditingController();
  final _varietyController = TextEditingController();
  final _plantingDateController = TextEditingController();
  final _harvestDateController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _cropNameController.dispose();
    _varietyController.dispose();
    _plantingDateController.dispose();
    _harvestDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final crop = CropRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      farmerId: widget.user.uid,
      cropName: _cropNameController.text.trim(),
      variety: _varietyController.text.trim(),
      plantingDate: _plantingDateController.text.trim(),
      harvestDate: _harvestDateController.text.trim(),
      notes: _notesController.text.trim(),
    );

    try {
      await ProviderScope.containerOf(
        context,
      ).read(farmCropRepositoryProvider).addCrop(crop);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crop record saved to Firestore')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop Records')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _cropNameController,
                decoration: const InputDecoration(labelText: 'Crop name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the crop name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _varietyController,
                decoration: const InputDecoration(labelText: 'Variety'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plantingDateController,
                decoration: const InputDecoration(labelText: 'Planting date'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _harvestDateController,
                decoration: const InputDecoration(labelText: 'Harvest date'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Save crop record'),
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved crop records',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: operationsOf(
                  context,
                ).watch('cropRecords', ownerId: widget.user.uid),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('No crop records saved yet.');
                  }

                  final crops = snapshot.data!.docs
                      .map((doc) => CropRecord.fromMap(doc.data()))
                      .toList();

                  return Column(
                    children: crops
                        .map(
                          (crop) => Card(
                            child: ListTile(
                              title: Text(crop.cropName),
                              subtitle: Text(
                                'Variety: ${crop.variety} • Planting: ${crop.plantingDate}',
                              ),
                              trailing: Text(crop.harvestDate),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetectionScreen extends StatelessWidget {
  final UserProfile user;
  const DetectionScreen({super.key, required this.user});
  @override
  Widget build(BuildContext context) => DetectionWorkspace(user: user);
}

class RecommendationScreen extends StatefulWidget {
  final UserProfile user;

  const RecommendationScreen({super.key, required this.user});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  final _issueController = TextEditingController();
  final _cropController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _issueController.dispose();
    _cropController.dispose();
    super.dispose();
  }

  Future<void> _saveRecommendation() async {
    if (_issueController.text.trim().isEmpty ||
        _cropController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both the crop and issue to generate advice.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final issue = _issueController.text.trim().toLowerCase();
    final crop = _cropController.text.trim();

    final diseaseRecommendation = _buildDiseaseAdvice(issue, crop);
    final pestRecommendation = _buildPestAdvice(issue, crop);
    final treatmentRecommendation = _buildTreatmentAdvice(issue, crop);
    final fertilizerRecommendation = _buildFertilizerAdvice(issue, crop);

    try {
      if (Firebase.apps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recommendation saved locally for preview.'),
          ),
        );
        return;
      }

      await operationsOf(context).saveRecommendationBundle(
        recommendation: {
          'farmerId': widget.user.uid,
          'crop': crop,
          'issue': issue,
          'diseaseRecommendation': diseaseRecommendation,
          'pestRecommendation': pestRecommendation,
          'treatmentRecommendation': treatmentRecommendation,
          'fertilizerRecommendation': fertilizerRecommendation,
          'createdAt': DateTime.now().toIso8601String(),
        },
        disease: {
          'crop': crop,
          'issue': issue,
          'advice': diseaseRecommendation,
        },
        pest: {'crop': crop, 'issue': issue, 'advice': pestRecommendation},
        treatment: {
          'crop': crop,
          'issue': issue,
          'advice': treatmentRecommendation,
        },
        fertilizer: {
          'crop': crop,
          'issue': issue,
          'advice': fertilizerRecommendation,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recommendation advisory saved to Firestore'),
        ),
      );
      _issueController.clear();
      _cropController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _buildDiseaseAdvice(String issue, String crop) {
    if (issue.contains('blight')) {
      return 'Remove infected leaves immediately, improve air circulation, and apply copper-based fungicide if the field is severely affected.';
    }
    if (issue.contains('mildew')) {
      return 'Reduce humidity around the canopy, prune dense growth, and use a broad-spectrum fungicide for prevention.';
    }
    return 'Inspect the crop for early symptoms, rotate fields where possible, and keep the field dry to reduce disease spread.';
  }

  String _buildPestAdvice(String issue, String crop) {
    if (issue.contains('pest') || issue.contains('insect')) {
      return 'Use pheromone traps, remove infested plant parts, and apply eco-friendly insecticides only when the threshold is exceeded.';
    }
    return 'Monitor weekly for pests, encourage beneficial insects, and scout the field after sunset for active infestations.';
  }

  String _buildTreatmentAdvice(String issue, String crop) {
    if (issue.contains('blight')) {
      return 'Treat with a recommended fungicide, sanitize tools, and avoid overhead watering to reduce reinfection.';
    }
    return 'Follow a targeted treatment plan for the detected problem and keep records of application dates for $crop.';
  }

  String _buildFertilizerAdvice(String issue, String crop) {
    if (issue.contains('blight')) {
      return 'Apply balanced NPK with additional potassium and avoid excess nitrogen, which can weaken plant resistance.';
    }
    return 'Use soil testing to match fertilizer to the needs of $crop and avoid over-fertilizing.';
  }

  @override
  Widget build(BuildContext context) {
    final firestoreReady = Firebase.apps.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations & Advice')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Turn a detected issue into practical next steps for treatment, prevention, fertilizer and soil care.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cropController,
              decoration: const InputDecoration(labelText: 'Crop'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issueController,
              decoration: const InputDecoration(
                labelText: 'Issue or disease name',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveRecommendation,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Generate recommendations'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Saved advisory records',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: !firestoreReady
                  ? const Stream.empty()
                  : operationsOf(context).watch('recommendations'),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('No advisory records yet.');
                }

                final recommendations = snapshot.data!.docs
                    .map((doc) => RecommendationRecord.fromMap(doc.data()))
                    .toList();

                return Column(
                  children: recommendations
                      .map(
                        (item) => Card(
                          child: ListTile(
                            title: Text(item.crop),
                            subtitle: Text(
                              '${item.issue} • ${item.treatmentRecommendation}',
                            ),
                            trailing: Text(
                              item.createdAt.isEmpty
                                  ? ''
                                  : item.createdAt.substring(0, 10),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class KnowledgeBaseScreen extends StatefulWidget {
  final UserProfile user;

  const KnowledgeBaseScreen({super.key, required this.user});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _causesController = TextEditingController();
  final _preventionController = TextEditingController();
  final _treatmentController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _symptomsController.dispose();
    _causesController.dispose();
    _preventionController.dispose();
    _treatmentController.dispose();
    super.dispose();
  }

  Future<void> _saveKnowledgeEntry() async {
    if (_titleController.text.trim().isEmpty ||
        _categoryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and category first.')),
      );
      return;
    }

    setState(() => _saving = true);

    final entry = KnowledgeEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      category: _categoryController.text.trim(),
      description: _descriptionController.text.trim(),
      symptoms: _symptomsController.text.trim(),
      causes: _causesController.text.trim(),
      preventionMethods: _preventionController.text.trim(),
      treatmentMethods: _treatmentController.text.trim(),
      imageUrl: '',
      createdAt: DateTime.now().toIso8601String(),
    );

    try {
      if (Firebase.apps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Knowledge base entry saved locally for preview.'),
          ),
        );
        return;
      }

      await operationsOf(context).saveKnowledgeBundle({
        'id': entry.id,
        'title': entry.title,
        'category': entry.category,
        'description': entry.description,
        'symptoms': entry.symptoms,
        'causes': entry.causes,
        'preventionMethods': entry.preventionMethods,
        'treatmentMethods': entry.treatmentMethods,
        'imageUrl': entry.imageUrl,
        'createdAt': entry.createdAt,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Knowledge base entry saved to Firestore'),
        ),
      );
      _titleController.clear();
      _categoryController.clear();
      _descriptionController.clear();
      _symptomsController.clear();
      _causesController.clear();
      _preventionController.clear();
      _treatmentController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreReady = Firebase.apps.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Base')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create or review crop, disease and pest reference entries for your farm team.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category (Crop, Disease, Pest)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symptomsController,
              decoration: const InputDecoration(labelText: 'Symptoms'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _causesController,
              decoration: const InputDecoration(labelText: 'Causes'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _preventionController,
              decoration: const InputDecoration(
                labelText: 'Prevention methods',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _treatmentController,
              decoration: const InputDecoration(labelText: 'Treatment methods'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveKnowledgeEntry,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save knowledge entry'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Knowledge entries',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: !firestoreReady
                  ? const Stream.empty()
                  : operationsOf(context).watch('crops'),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('No knowledge entries yet.');
                }

                final entries = snapshot.data!.docs
                    .map((doc) => KnowledgeEntry.fromMap(doc.data()))
                    .toList();

                return Column(
                  children: entries
                      .map(
                        (entry) => Card(
                          child: ListTile(
                            title: Text(entry.title),
                            subtitle: Text(
                              '${entry.category} • ${entry.description}',
                            ),
                            trailing: Text(
                              entry.createdAt.isEmpty
                                  ? ''
                                  : entry.createdAt.substring(0, 10),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green.shade700),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.shade900,
              Colors.green.shade700,
              Colors.lightGreen.shade400,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.eco_rounded,
                          color: Colors.green.shade700,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Agriculture Pest System',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Smart farming access',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Secure farmer access, premium crop monitoring, and real-time agricultural intelligence in one trusted platform.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RegisterScreen(
                                  onRegister: (profile, password) async {
                                    final gateState = context
                                        .findAncestorStateOfType<
                                          _AuthGateState
                                        >();
                                    await gateState?._registerUser(
                                      profile,
                                      password,
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Create account'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.green.shade200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () async {
                            final gateState = context
                                .findAncestorStateOfType<_AuthGateState>();
                            await gateState?._signInWithGoogle();
                          },
                          icon: const Icon(Icons.g_mobiledata),
                          label: const Text('Continue with Google'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LoginScreen(
                                  onLogin: (email, password) async {
                                    final gateState = context
                                        .findAncestorStateOfType<
                                          _AuthGateState
                                        >();
                                    await gateState?._loginUser(
                                      email,
                                      password,
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.login),
                          label: const Text('Login'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Protected farm access and secure analytics for modern agriculture teams.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  final Future<void> Function(UserProfile profile, String password) onRegister;

  const RegisterScreen({super.key, required this.onRegister});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  UserRole _selectedRole = UserRole.farmer;
  AccountStatus _selectedStatus = AccountStatus.active;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = UserProfile(
      uid: '',
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      location: _locationController.text.trim(),
      role: _selectedRole,
      accountStatus: _selectedStatus,
      profileImage: '',
      authProvider: 'email',
    );

    try {
      await widget.onRegister(profile, _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.green.shade800,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: Colors.green.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.agriculture_rounded,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Join the trusted agriculture platform',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create your professional farm profile and unlock modern monitoring tools.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              prefixIcon: Icon(Icons.call_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationController,
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<UserRole>(
                            initialValue: _selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            items: UserRole.values
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role,
                                    child: Text(role.displayName),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedRole = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<AccountStatus>(
                            initialValue: _selectedStatus,
                            decoration: const InputDecoration(
                              labelText: 'Account status',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                            items: AccountStatus.values
                                .map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status.displayName),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedStatus = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.length < 6
                                ? 'Use at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _saving ? null : _submit,
                              child: _saving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Create account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final Future<void> Function(String email, String password) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await widget.onLogin(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome back'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.green.shade800,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: Colors.green.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.terrain_outlined,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Sign in to your farm workspace',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Access your crop insights, disease analysis, and secure advisory tools.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.length < 6
                                ? 'Enter your password'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Login'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final UserProfile user;
  final Future<void> Function(UserProfile profile) onUpdate;
  final Future<void> Function() onLogout;
  final Future<void> Function(String email) onResetPassword;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onUpdate,
    required this.onLogout,
    required this.onResetPassword,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _locationController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _phoneController = TextEditingController(text: widget.user.phone);
    _locationController = TextEditingController(text: widget.user.location);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final updated = widget.user.copyWith(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      location: _locationController.text.trim(),
    );
    try {
      await widget.onUpdate(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetPassword() async {
    try {
      await widget.onResetPassword(widget.user.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset sent to ${widget.user.email}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton.icon(
            onPressed: () async => widget.onLogout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${widget.user.fullName}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.user.email,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Role: ${widget.user.role.displayName}')),
                Chip(
                  label: Text(
                    'Status: ${widget.user.accountStatus.displayName}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save profile'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetPassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Reset password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
