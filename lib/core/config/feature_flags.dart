import 'package:flutter/foundation.dart';

class FeatureFlags extends ChangeNotifier {
  FeatureFlags._();
  static final instance = FeatureFlags._();

  bool maintenanceMode = false;
  bool aiDetectionEnabled = true;
  bool uploadsEnabled = true;
  String maintenanceMessage =
      'The service is temporarily undergoing maintenance. Please retry later.';
  String minimumSupportedVersion = '1.0.0';

  void update({
    required bool maintenanceMode,
    required String maintenanceMessage,
    required bool aiDetectionEnabled,
    required bool uploadsEnabled,
    required String minimumSupportedVersion,
  }) {
    this.maintenanceMode = maintenanceMode;
    this.maintenanceMessage = maintenanceMessage;
    this.aiDetectionEnabled = aiDetectionEnabled;
    this.uploadsEnabled = uploadsEnabled;
    this.minimumSupportedVersion = minimumSupportedVersion;
    notifyListeners();
  }
}
