import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DiagnosticOutcome { success, failure, cancelled, offline, timeout }

class DiagnosticEvent {
  static const _sensitiveFragments = <String>{
    'email',
    'name',
    'password',
    'token',
    'secret',
    'phone',
    'address',
    'image',
    'latitude',
    'longitude',
    'uid',
    'userid',
  };

  final String name;
  final String category;
  final DiagnosticOutcome outcome;
  final DateTime timestamp;
  final Map<String, Object> attributes;

  DiagnosticEvent({
    required this.name,
    required this.category,
    required this.outcome,
    DateTime? timestamp,
    Map<String, Object?> attributes = const {},
  }) : timestamp = timestamp ?? DateTime.now().toUtc(),
       attributes = _sanitize(attributes);

  static Map<String, Object> _sanitize(Map<String, Object?> values) {
    final safe = <String, Object>{};
    for (final entry in values.entries) {
      final normalized = entry.key.toLowerCase().replaceAll(
        RegExp(r'[^a-z]'),
        '',
      );
      if (_sensitiveFragments.any(normalized.contains)) continue;
      final value = entry.value;
      if (value is num || value is bool) safe[entry.key] = value as Object;
      if (value is String && value.length <= 80) safe[entry.key] = value;
    }
    return Map.unmodifiable(safe);
  }

  Map<String, Object> toJson() => {
    'name': name,
    'category': category,
    'outcome': outcome.name,
    'timestamp': timestamp.toIso8601String(),
    'attributes': attributes,
  };
}

abstract interface class DiagnosticSink {
  void record(DiagnosticEvent event);
}

class DebugDiagnosticSink implements DiagnosticSink {
  const DebugDiagnosticSink();

  @override
  void record(DiagnosticEvent event) => debugPrint(jsonEncode(event.toJson()));
}

class DelegatingDiagnosticSink implements DiagnosticSink {
  DiagnosticSink delegate;
  DelegatingDiagnosticSink(this.delegate);

  @override
  void record(DiagnosticEvent event) => delegate.record(event);
}

final diagnosticSink = DelegatingDiagnosticSink(const DebugDiagnosticSink());
