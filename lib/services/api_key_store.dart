import 'package:shared_preferences/shared_preferences.dart';

/// Secure-enough local storage for user-provided API keys.
/// Keys are stored in SharedPreferences (device-local, not synced to cloud
/// unless the user has enabled platform backup).
class ApiKeyStore {
  ApiKeyStore({SharedPreferences? preferences})
      : _prefs = preferences;

  SharedPreferences? _prefs;
  static const _prefix = 'edgewise_api_key_';
  static const _keys = <String, String>{
    'rapidApi': '${_prefix}rapid_api',
    'visualCrossing': '${_prefix}visual_crossing',
    'hkoWeather': '${_prefix}hko_weather',
  };

  Future<SharedPreferences> get _storage async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // --- RapidAPI (API-Football) ---
  Future<String> get rapidApiKey async =>
      (await _storage).getString(_keys['rapidApi']!) ?? '';

  Future<void> setRapidApiKey(String value) async =>
      (await _storage).setString(_keys['rapidApi']!, value.trim());

  // --- Visual Crossing ---
  Future<String> get visualCrossingKey async =>
      (await _storage).getString(_keys['visualCrossing']!) ?? '';

  Future<void> setVisualCrossingKey(String value) async =>
      (await _storage).setString(_keys['visualCrossing']!, value.trim());

  // --- HKO Weather ---
  Future<String> get hkoWeatherKey async =>
      (await _storage).getString(_keys['hkoWeather']!) ?? '';

  Future<void> setHkoWeatherKey(String value) async =>
      (await _storage).setString(_keys['hkoWeather']!, value.trim());

  /// Returns a map of all configured keys (non-empty).
  Future<Map<String, String>> configuredKeys() async {
    final prefs = await _storage;
    final result = <String, String>{};
    for (final entry in _keys.entries) {
      final value = prefs.getString(entry.value) ?? '';
      if (value.isNotEmpty) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  /// Whether at least one optional API key has been provided.
  Future<bool> get hasAnyKey async =>
      (await configuredKeys()).isNotEmpty;
}
