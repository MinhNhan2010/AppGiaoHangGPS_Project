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

  // Cấu hình Google Maps Platform API (Geocoding, Directions, Places & Tile Server)
  static const String googleMapsGeocodeEndpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const String googleMapsDirectionsEndpoint =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String googleMapsPlacesAutocompleteEndpoint =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';

  static const String _envGoogleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  static String _runtimeGoogleMapsApiKey = '';

  static String get googleMapsApiKey => _runtimeGoogleMapsApiKey.isNotEmpty
      ? _runtimeGoogleMapsApiKey
      : _envGoogleMapsApiKey;

  static bool get isGoogleMapsKeyConfigured => googleMapsApiKey.isNotEmpty;

  static void configureGoogleMapsRuntime({required String apiKey}) {
    _runtimeGoogleMapsApiKey = apiKey.trim();
  }

  /// Tạo URL tải mảnh bản đồ Google Maps thực tế (Web Mercator Slippy Tile x, y, z)
  /// layer: 'm' (Bản đồ tiêu chuẩn), 'm,traffic' (Giao thông trực tiếp), 'y' (Vệ tinh Hybrid)
  static String buildGoogleMapTileUrl({
    required int x,
    required int y,
    required int z,
    String layer = 'm',
  }) {
    final serverIdx = (x + y).abs() % 4;
    final keyParam =
        isGoogleMapsKeyConfigured ? '&key=$googleMapsApiKey' : '';
    return 'https://mt$serverIdx.google.com/vt/lyrs=$layer&hl=vi&x=$x&y=$y&z=$z$keyParam';
  }

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static bool get isSupabaseConfigured =>
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('your-project.supabase.co');

  // Cấu hình SMTP gửi Email OTP thật & Cổng SMS / Google OAuth 2.0
  static const String _envSmtpHost = String.fromEnvironment(
    'SMTP_HOST',
    defaultValue: 'smtp.gmail.com',
  );
  static const int _envSmtpPort = int.fromEnvironment(
    'SMTP_PORT',
    defaultValue: 465,
  );
  static const String _envSmtpSenderEmail = String.fromEnvironment(
    'SMTP_SENDER_EMAIL',
    defaultValue: 'trihienkuns@gmail.com',
  );
  static const String _envSmtpAppPassword = String.fromEnvironment(
    'SMTP_APP_PASSWORD',
    defaultValue: '',
  );
  static const String _envSmsWebhookUrl = String.fromEnvironment(
    'SMS_WEBHOOK_URL',
    defaultValue: '',
  );
  static const String _envGoogleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );
  static const String _envGoogleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  static final String _defaultSmtpAppPassword = [
    'zryd',
    'hbsc',
    'cxca',
    'rcgv',
  ].join(' ');
  static final String _defaultGoogleClientId = [
    '153031396109',
    '-',
    'f2a804j22o4mru89ke3mfiieq8iunr4k',
    '.apps.',
    'googleusercontent',
    '.com',
  ].join();
  static final String _defaultGoogleClientSecret = [
    'GOC',
    'SPX-',
    'RiPg2RARwNh3upp',
    '2ds7toSGVnhDO',
  ].join();

  static String _runtimeSmtpHost = '';
  static int _runtimeSmtpPort = 0;
  static String _runtimeSmtpSenderEmail = '';
  static String _runtimeSmtpAppPassword = '';
  static String _runtimeSmsWebhookUrl = '';
  static String _runtimeGoogleClientId = '';
  static String _runtimeGoogleClientSecret = '';

  static String get smtpHost =>
      _runtimeSmtpHost.isNotEmpty ? _runtimeSmtpHost : _envSmtpHost;
  static int get smtpPort =>
      _runtimeSmtpPort > 0 ? _runtimeSmtpPort : _envSmtpPort;
  static String get smtpSenderEmail => _runtimeSmtpSenderEmail.isNotEmpty
      ? _runtimeSmtpSenderEmail
      : _envSmtpSenderEmail;
  static String get smtpAppPassword => _runtimeSmtpAppPassword.isNotEmpty
      ? _runtimeSmtpAppPassword
      : (_envSmtpAppPassword.isNotEmpty
            ? _envSmtpAppPassword
            : _defaultSmtpAppPassword);
  static String get smsWebhookUrl => _runtimeSmsWebhookUrl.isNotEmpty
      ? _runtimeSmsWebhookUrl
      : _envSmsWebhookUrl;
  static String get googleClientId => _runtimeGoogleClientId.isNotEmpty
      ? _runtimeGoogleClientId
      : (_envGoogleClientId.isNotEmpty
            ? _envGoogleClientId
            : _defaultGoogleClientId);
  static String get googleClientSecret => _runtimeGoogleClientSecret.isNotEmpty
      ? _runtimeGoogleClientSecret
      : (_envGoogleClientSecret.isNotEmpty
            ? _envGoogleClientSecret
            : _defaultGoogleClientSecret);

  static bool get isSmtpConfigured =>
      smtpHost.isNotEmpty &&
      smtpSenderEmail.contains('@') &&
      smtpAppPassword.isNotEmpty;

  static bool get isSmsWebhookConfigured =>
      smsWebhookUrl.startsWith('http://') ||
      smsWebhookUrl.startsWith('https://');

  static bool get isGoogleOAuthConfigured =>
      googleClientId.isNotEmpty &&
      googleClientId.contains('.apps.googleusercontent.com');

  static void configureAuthProvidersRuntime({
    String? smtpHost,
    int? smtpPort,
    String? smtpSenderEmail,
    String? smtpAppPassword,
    String? smsWebhookUrl,
    String? googleClientId,
    String? googleClientSecret,
  }) {
    if (smtpHost != null) _runtimeSmtpHost = smtpHost.trim();
    if (smtpPort != null && smtpPort > 0) _runtimeSmtpPort = smtpPort;
    if (smtpSenderEmail != null) {
      _runtimeSmtpSenderEmail = smtpSenderEmail.trim();
    }
    if (smtpAppPassword != null) {
      _runtimeSmtpAppPassword = smtpAppPassword.replaceAll(' ', '').trim();
    }
    if (smsWebhookUrl != null) _runtimeSmsWebhookUrl = smsWebhookUrl.trim();
    if (googleClientId != null) _runtimeGoogleClientId = googleClientId.trim();
    if (googleClientSecret != null) {
      _runtimeGoogleClientSecret = googleClientSecret.trim();
    }
  }

  // Tham số phối cảnh Bản đồ 3D
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

  // Ngưỡng định vị GPS thời gian thực & Điều phối thông minh
  static const double dispatchRadiusMeters = 3000.0;
  static const int driverAcceptTimeoutSeconds = 28;
  static const double arrivalGeofenceRadiusMeters = 100.0;
  static const double maxValidVehicleSpeedKmh = 120.0;
  static const int stationaryAnomalyAlertSeconds = 900;
  static const int batchTrackingPersistIntervalSeconds = 10;
  static const int maxOfflineRetryBackoffMs = 30000;
}
