class EnvConfig {
  const EnvConfig._();

  static const String _envSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String _envSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static String _runtimeSupabaseUrl = '';
  static String _runtimeSupabaseAnonKey = '';

  static String get supabaseUrl =>
      _runtimeSupabaseUrl.isNotEmpty ? _runtimeSupabaseUrl : _envSupabaseUrl;

  static String get supabaseAnonKey => _runtimeSupabaseAnonKey.isNotEmpty
      ? _runtimeSupabaseAnonKey
      : _envSupabaseAnonKey;

  static void configureSupabaseRuntime({
    required String url,
    required String anonKey,
  }) {
    _runtimeSupabaseUrl = url.trim();
    _runtimeSupabaseAnonKey = anonKey.trim();
  }

  static const String nominatimSearchEndpoint =
      'https://nominatim.openstreetmap.org/search';
  static const String osrmRouteEndpoint =
      'https://router.project-osrm.org/route/v1/driving';

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static bool get isSupabaseConfigured =>
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('your-project.supabase.co');


  // 3D Map Perspective Parameters (Chapter 8.6 - Table 16)
  static const double map3dDefaultPitch = 55.0;
  static const double map3dMinPitch = 45.0;
  static const double map3dMaxPitch = 60.0;
  static const double map3dNavigationZoom = 17.0;
  static const double map2dOverviewZoom = 14.5;
  static const double buildingExtrusionOpacity = 0.65;
  static const double routeRibbonWidthPx = 8.0;
  static const double routeCasingWidthPx = 2.0;
  static const int mapMaxFps = 30;
  static const int lowBattery2dFallbackPercent = 20;

  // Real-time GPS & Smart Dispatch Thresholds (Chapters 4, 10, 14, 15)
  static const double dispatchRadiusMeters = 3000.0;
  static const int driverAcceptTimeoutSeconds = 20;
  static const double arrivalGeofenceRadiusMeters = 100.0;
  static const double maxValidVehicleSpeedKmh = 120.0;
  static const int stationaryAnomalyAlertSeconds = 900;
  static const int batchTrackingPersistIntervalSeconds = 10;
  static const int maxOfflineRetryBackoffMs = 30000;
}
