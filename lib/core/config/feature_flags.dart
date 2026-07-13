class FeatureFlags {
  FeatureFlags._();
  static final instance = FeatureFlags._();

  bool maintenanceMode = false;
  bool aiDetectionEnabled = true;
  bool uploadsEnabled = true;
  String maintenanceMessage =
      'The service is temporarily undergoing maintenance. Please retry later.';
  String minimumSupportedVersion = '1.0.0';
}
