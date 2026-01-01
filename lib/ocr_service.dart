import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class OcrService {
  String? _serverUrl;
  String? _apiToken;

  Future<void> initialize() async {
    final config = await ConfigService.getOcrConfig();
    _serverUrl = config['url'];
    _apiToken = config['token'];
  }

  void setConfig(String url, String token) {
    if (url.isEmpty) return;
    if (!url.startsWith("http")) url = "http://$url";
    if (!url.endsWith("/ocr")) {
      url = url.endsWith("/") ? "${url}ocr" : "$url/ocr";
    }
    
    _serverUrl = url;
    _apiToken = token;
    
    ConfigService.saveOcrConfig(url, token);
  }

  bool hasConfig() {
    return _serverUrl != null && _serverUrl!.isNotEmpty;
  }

  Future<String?> recognizeText(Uint8List imageBytes) async {
    if (!hasConfig()) return "请先在设置中配置 OCR 服务器地址";

    try {
      final uri = Uri.parse(_serverUrl!);
      var request = http.MultipartRequest('POST', uri);
      
      // RapidOCR 鉴权
      if (_apiToken != null && _apiToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_apiToken';
      }

      // [修改] 使用 fromBytes 直接上传内存数据
      // filename 是必须的，但可以是任意假名字，服务器通常只看内容
      request.files.add(http.MultipartFile.fromBytes(
        'image_file', 
        imageBytes,
        filename: 'screenshot_temp.png' 
      ));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // 解析 RapidOCR 格式
        if (data is Map && data.isNotEmpty) {
          StringBuffer sb = StringBuffer();
          for (var item in data.values) {
            if (item is Map && item.containsKey('rec_txt')) {
              sb.writeln(item['rec_txt']);
            }
          }
          String result = sb.toString().trim();
          return result.isEmpty ? "未识别到文字" : result;
        } else {
          return "未识别到文字";
        }
      } else if (response.statusCode == 401) {
        return "OCR 认证失败：密码错误";
      } else {
        return "OCR 服务器错误 (${response.statusCode})";
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
      return "连接 OCR 服务器失败";
    }
  }
}