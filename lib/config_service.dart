import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  // 统一变量名
  static const String _deepSeekKey = 'deepseek_api_key';
  static const String _baiduApiKey = 'baidu_api_key';
  static const String _baiduSecretKey = 'baidu_secret_key';
  static const String _firstRunKey = 'first_run';

  // --- 通用 ---
  static Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstRunKey) ?? true;
  }

  static Future<void> setNotFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunKey, false);
  }

  // --- DeepSeek Key ---
  static Future<void> saveDeepSeekKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deepSeekKey, key);
  }

  static Future<String?> getDeepSeekKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deepSeekKey);
  }

  // --- 百度 OCR Key ---
  static Future<void> saveBaiduKeys(String apiKey, String secretKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baiduApiKey, apiKey);
    await prefs.setString(_baiduSecretKey, secretKey);
  }

  static Future<Map<String, String?>> getBaiduKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString(_baiduApiKey),
      'secretKey': prefs.getString(_baiduSecretKey),
    };
  }

  // --- 清除 ---
  static Future<void> clearAllKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deepSeekKey);
    await prefs.remove(_baiduApiKey);
    await prefs.remove(_baiduSecretKey);
  }

  // --- 检查配置 ---
  // [这里就是你问的地方]
  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final ds = prefs.getString(_deepSeekKey);
    
    // 逻辑：只要 DeepSeek Key 存在且不为空，就算配置完成了。
    // 百度 Key 是选填的，不影响“应用是否已配置”的状态。
    return ds != null && ds.isNotEmpty;
  }
}