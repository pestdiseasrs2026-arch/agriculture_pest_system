enum AppFlavor { development, staging, production }

abstract final class AppEnvironment {
  static const name = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static AppFlavor get flavor => switch (name.toLowerCase()) {
    'production' || 'prod' => AppFlavor.production,
    'staging' || 'stage' => AppFlavor.staging,
    _ => AppFlavor.development,
  };

  static bool get isProduction => flavor == AppFlavor.production;
}
