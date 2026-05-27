/// Central configuration for backend URLs.
///
/// Override at build time with --dart-define:
///   flutter run --dart-define=API_BASE=https://api.example.com
///   flutter build apk --dart-define=API_BASE=https://api.example.com
///
/// Defaults assume an Android emulator pointing at the host's localhost
/// FastAPI on port 8000.
class ApiConfig {
  static const String _defaultBase = 'http://10.0.2.2:8000';
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: _defaultBase,
  );

  static String get restRoot => '$apiBase/api';
  static String get apiV1 => '$apiBase/api/v1';
  static String get wsStream {
    final ws = apiBase.replaceFirst(RegExp(r'^http'), 'ws');
    return '$ws/api/v1/stream';
  }
}
