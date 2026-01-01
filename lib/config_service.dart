import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _deepSeekKey = 'deepseek_api_key';
  static const String _ocrUrlKey = 'ocr_server_url'; 
  static const String _ocrTokenKey = 'ocr_server_token';
  static const String _firstRunKey = 'first_run';

  static Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstRunKey) ?? true;
  }

  static Future<void> setNotFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunKey, false);
  }

  // DeepSeek Key
  static Future<void> saveDeepSeekKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deepSeekKey, key);
  }

  static Future<String?> getDeepSeekKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deepSeekKey);
  }

  // --- OCR 配置 (私有服务器) ---
  static Future<void> saveOcrConfig(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ocrUrlKey, url);
    await prefs.setString(_ocrTokenKey, token);
  }

  static Future<Map<String, String?>> getOcrConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString(_ocrUrlKey),
      'token': prefs.getString(_ocrTokenKey),
    };
  }
  
  static Future<void> clearAllKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deepSeekKey);
    await prefs.remove(_ocrUrlKey);
    await prefs.remove(_ocrTokenKey);
    await prefs.setBool(_firstRunKey, true);
  }
}