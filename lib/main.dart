import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/logging/app_error_reporter.dart';
import 'core/services/production_operations.dart';
import 'firebase_options.dart';

export 'app/app.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        appErrorReporter.record(
          details.exception,
          details.stack ?? StackTrace.current,
          fatal: true,
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        appErrorReporter.record(error, stackTrace, fatal: true);
        return true;
      };

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await ProductionOperations.initialize();
      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stackTrace) {
      appErrorReporter.record(error, stackTrace, fatal: true);
    },
  );
}
