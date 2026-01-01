import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class DeepSeekService {
  String? _apiKey;

  Future<void> initialize() async {
    _apiKey = await ConfigService.getDeepSeekKey();
  }

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    ConfigService.saveDeepSeekKey(apiKey);
  }

  bool hasApiKey() {
    return _apiKey != null && _apiKey!.isNotEmpty;
  }

  Future<String> translate(String text) async {
    if (!hasApiKey()) {
      return "请先配置 DeepSeek API Key";
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
              "content": 
                "你是一位精通多国语言的资深翻译专家。请将用户输入的文本进行高质量翻译。\n"
                "规则：\n"
                "1. 自动检测原文语言。\n"
                "2. 如果原文是中文，请翻译成英文；如果原文是英文或其他语言，请翻译成简体中文。\n"
                "3. 翻译风格要求：信、达、雅。保持原文的语境、语气和逻辑，专业术语需准确翻译。\n"
                "4. 严禁输出任何解释、注脚、拼音或无关的对话内容，仅直接输出最终的翻译结果。"
            },
            {"role": "user", "content": text}
          ],
          "temperature": 0.3, // 降低温度以获得更准确的翻译
          "stream": false
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final translatedText = data['choices'][0]['message']['content'];
        return translatedText.trim();
      } else if (response.statusCode == 401) {
        return "API Key 无效或过期";
      } else {
        return "翻译服务异常 (${response.statusCode})";
      }
    } catch (e) {
      return "网络错误: $e";
    }
  }
}