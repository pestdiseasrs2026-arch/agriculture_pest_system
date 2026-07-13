import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../config/feature_flags.dart';
import '../logging/app_error_reporter.dart';
import '../logging/diagnostic_event.dart';

abstract final class ProductionOperations {
  static StreamSubscription<RemoteConfigUpdate>? _updates;

  static Future<void> initialize() async {
    await _activateAppCheck();
    await _configureRemoteConfig();

    if (AppEnvironment.isProduction) {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          true,
        );
        appErrorReporter.delegate = const FirebaseAppErrorReporter();
      }
      diagnosticSink.delegate = FirebaseDiagnosticSink(
        FirebaseAnalytics.instance,
      );
    } else {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(false);
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          false,
        );
      }
    }
  }

  static Future<void> _activateAppCheck() async {
    const webKey = String.fromEnvironment('APP_CHECK_WEB_KEY');
    if (kIsWeb && webKey.isEmpty) {
      if (AppEnvironment.isProduction) {
        throw StateError('APP_CHECK_WEB_KEY is required in production.');
      }
      return;
    }
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: AppEnvironment.isProduction
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: AppEnvironment.isProduction
          ? const AppleAppAttestWithDeviceCheckFallbackProvider()
          : const AppleDebugProvider(),
      providerWeb: webKey.isEmpty ? null : ReCaptchaV3Provider(webKey),
    );
  }

  static Future<void> _configureRemoteConfig() async {
    final config = FirebaseRemoteConfig.instance;
    await config.setDefaults(const {
      'maintenance_mode': false,
      'maintenance_message':
          'The service is temporarily undergoing maintenance. Please retry later.',
      'ai_detection_enabled': true,
      'uploads_enabled': true,
      'minimum_supported_version': '1.0.0',
    });
    await config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 20),
        minimumFetchInterval: AppEnvironment.isProduction
            ? const Duration(hours: 1)
            : const Duration(minutes: 5),
      ),
    );
    try {
      await config.fetchAndActivate();
    } catch (_) {
      // Safe defaults remain active while offline or throttled.
    }
    _apply(config);
    if (!kIsWeb) {
      await _updates?.cancel();
      _updates = config.onConfigUpdated.listen((_) async {
        await config.activate();
        _apply(config);
      });
    }
  }

  static void _apply(FirebaseRemoteConfig config) {
    final flags = FeatureFlags.instance;
    flags.maintenanceMode = config.getBool('maintenance_mode');
    flags.maintenanceMessage = config.getString('maintenance_message');
    flags.aiDetectionEnabled = config.getBool('ai_detection_enabled');
    flags.uploadsEnabled = config.getBool('uploads_enabled');
    flags.minimumSupportedVersion = config.getString(
      'minimum_supported_version',
    );
  }
}

class FirebaseDiagnosticSink implements DiagnosticSink {
  final FirebaseAnalytics analytics;
  const FirebaseDiagnosticSink(this.analytics);

  @override
  void record(DiagnosticEvent event) {
    unawaited(
      analytics.logEvent(
        name: event.name,
        parameters: {
          'category': event.category,
          'outcome': event.outcome.name,
          ...event.attributes,
        },
      ),
    );
  }
}

class FirebaseAppErrorReporter implements AppErrorReporter {
  const FirebaseAppErrorReporter();

  @override
  void record(Object error, StackTrace stackTrace, {bool fatal = false}) {
    diagnosticSink.record(
      DiagnosticEvent(
        name: fatal ? 'uncaught_fatal_error' : 'handled_error',
        category: 'application',
        outcome: DiagnosticOutcome.failure,
        attributes: {'errorType': error.runtimeType.toString()},
      ),
    );
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        StateError(error.runtimeType.toString()),
        stackTrace,
        fatal: fatal,
        reason: 'Sanitized application error',
      ),
    );
  }
}
