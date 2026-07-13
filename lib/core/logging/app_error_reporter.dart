import 'package:flutter/foundation.dart';
import 'diagnostic_event.dart';

abstract interface class AppErrorReporter {
  void record(Object error, StackTrace stackTrace, {bool fatal = false});
}

class DebugAppErrorReporter implements AppErrorReporter {
  const DebugAppErrorReporter();

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
    debugPrint('${fatal ? 'FATAL' : 'ERROR'}: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class DelegatingAppErrorReporter implements AppErrorReporter {
  AppErrorReporter delegate;
  DelegatingAppErrorReporter(this.delegate);

  @override
  void record(Object error, StackTrace stackTrace, {bool fatal = false}) =>
      delegate.record(error, stackTrace, fatal: fatal);
}

final appErrorReporter = DelegatingAppErrorReporter(
  const DebugAppErrorReporter(),
);
