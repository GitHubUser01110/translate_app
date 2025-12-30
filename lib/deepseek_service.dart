import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class DeepSeekService {
  String? _apiKey;

  // 异步初始化，从配置中读取API Key
  Future<void> initialize() async {
    _apiKey = await ConfigService.getDeepSeekKey();
  }

  // 设置API Key
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    ConfigService.saveDeepSeekKey(apiKey);
  }

  // 检查是否有API Key
  bool hasApiKey() {
    return _apiKey != null && _apiKey!.isNotEmpty;
  }

  Future<String> translate(String text) async {
    // 如果没有API Key，提示用户配置
    if (!hasApiKey()) {
      return "请先在设置中配置 DeepSeek API Key\n(点击右上角设置图标)";
    }

    if (text.trim().isEmpty) return "";

    try {
      final response = await http.post(
        Uri.parse("https://api.deepseek.com/chat/completions"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {
              "role": "system",
              "content": "你是一个专业的翻译助手。请将用户输入的文本翻译成中文。如果原文已经是中文，则翻译成英文。请保持翻译准确、通顺，不要添加任何解释、注释或额外内容。直接输出翻译结果。"
            },
            {"role": "user", "content": text}
          ],
          "temperature": 0.7,
          "max_tokens": 2000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final translatedText = data['choices'][0]['message']['content'];
        return translatedText.trim();
      } else if (response.statusCode == 401) {
        return "API Key 无效，请检查并重新配置\n(点击右上角设置图标)";
      } else {
        return "翻译请求失败 (状态码: ${response.statusCode})";
      }
    } catch (e) {
      return "翻译出错: ${e.toString()}";
    }
  }
}