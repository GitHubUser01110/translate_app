import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class BaiduService {
  String? _apiKey;
  String? _secretKey;
  String? _accessToken;
  int _tokenExpiresAt = 0;

  // 初始化
  Future<void> initialize() async {
    final keys = await ConfigService.getBaiduKeys();
    _apiKey = keys['apiKey'];
    _secretKey = keys['secretKey'];
  }

  void setKeys(String apiKey, String secretKey) {
    _apiKey = apiKey;
    _secretKey = secretKey;
    _accessToken = null; // Key变了，Token作废
    ConfigService.saveBaiduKeys(apiKey, secretKey);
  }

  bool hasKeys() {
    return _apiKey != null && _apiKey!.isNotEmpty && 
           _secretKey != null && _secretKey!.isNotEmpty;
  }

  // 获取 Access Token
  Future<String?> _getAccessToken() async {
    // 如果现有 Token 还没过期（预留60秒缓冲），直接用
    if (_accessToken != null && DateTime.now().millisecondsSinceEpoch < _tokenExpiresAt - 60000) {
      return _accessToken;
    }

    if (!hasKeys()) return null;

    final url = "https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=$_apiKey&client_secret=$_secretKey";
    
    try {
      final response = await http.post(Uri.parse(url));
      final data = jsonDecode(response.body);
      
      if (data['access_token'] != null) {
        _accessToken = data['access_token'];
        // expires_in 是秒，转为毫秒时间戳
        _tokenExpiresAt = DateTime.now().millisecondsSinceEpoch + (data['expires_in'] as int) * 1000;
        return _accessToken;
      }
    } catch (e) {
      // [修改] 使用 debugPrint 替代 print，消除警告
      debugPrint("获取百度Token失败: $e");
    }
    return null;
  }

  // 进行文字识别
  Future<String?> recognizeText(File imageFile) async {
    final token = await _getAccessToken();
    if (token == null) return "请检查百度 API Key 配置";

    final url = "https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token=$token";
    
    try {
      // 1. 图片转 Base64
      List<int> imageBytes = await imageFile.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      // 2. 发送请求 (必须是 x-www-form-urlencoded)
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'image': base64Image},
      );

      // 3. 解析结果
      final data = jsonDecode(response.body);
      
      if (data['words_result'] != null) {
        List<dynamic> words = data['words_result'];
        // 将所有行的文字拼接起来
        StringBuffer sb = StringBuffer();
        for (var item in words) {
          sb.writeln(item['words']);
        }
        return sb.toString();
      } else if (data['error_msg'] != null) {
        return "OCR 错误: ${data['error_msg']}";
      }
    } catch (e) {
      return "网络请求失败: $e";
    }
    return null;
  }

  // [新增] 验证 Key 是否有效
  Future<void> verifyKeys(String apiKey, String secretKey) async {
    // 百度获取 Token 的接口
    final url = "https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=$apiKey&client_secret=$secretKey";
    
    try {
      final response = await http.post(Uri.parse(url));
      final data = jsonDecode(response.body);

      // 如果返回结果包含 error，说明验证失败
      if (data['error'] != null) {
        // error_description 通常包含具体的错误原因，比如 "unknown client id"
        throw "验证失败: ${data['error_description'] ?? 'Key 无效'}";
      }

      // 如果成功拿到 access_token，说明 Key 是对的
      if (data['access_token'] != null) {
        _accessToken = data['access_token']; // 顺便缓存一下 Token
        _tokenExpiresAt = DateTime.now().millisecondsSinceEpoch + (data['expires_in'] as int) * 1000;
        return; // 验证通过
      }
      
      throw "验证失败: 未知响应";
    } catch (e) {
      // 抛出异常给上层 UI 捕获
      throw e.toString(); 
    }
  }
}