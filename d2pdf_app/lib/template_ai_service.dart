import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:shared_preferences/shared_preferences.dart';
import 'layout_template.dart';

class AiServiceConfig {
  static const String _kApiBaseUrlKey = 'd2pdf_ai_api_base_url';
  static const String _kApiKey = 'd2pdf_ai_api_key';
  static const String _kModelKey = 'd2pdf_ai_model';

  // 默认快捷预设
  static const String defaultBaseUrl = 'https://api.siliconflow.cn/v1';
  static const String defaultModel = 'zai-org/GLM-5.3-Flash';

  static const List<String> presetModels = [
    'zai-org/GLM-5.3-Flash',
    'Qwen/Qwen3.8-27B',
    'moonshotai/Kimi-K2.7-Code',
    'Pro/moonshotai/Kimi-K2.6',
    'Qwen/Qwen3.6-35B-A3B',
  ];

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiBaseUrlKey) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiBaseUrlKey, url.trim());
  }

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key.trim());
  }

  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kModelKey);
    if (saved == null ||
        saved.isEmpty ||
        saved == 'deepseek-ai/DeepSeek-V4.1-Flash' ||
        saved.contains('Qwen2.5-VL-7B-Instruct')) {
      return defaultModel;
    }
    return saved;
  }

  static Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelKey, model.trim());
  }
}

class TemplateAiGenerator {
  /// 调用 AI 分析文本要求或参考图片，并返回生成的 LayoutTemplate
  static http.Client _createRobustClient() {
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 15);
    ioClient.badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(ioClient);
  }

  static Future<http.Response> _postWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 60),
    int maxRetries = 2,
  }) async {
    int attempts = 0;
    while (true) {
      attempts++;
      final client = _createRobustClient();
      try {
        final reqHeaders = Map<String, String>.from(headers);
        reqHeaders['Connection'] = 'close';
        reqHeaders['Accept'] = 'application/json';
        reqHeaders['User-Agent'] = 'D2PDF/1.2.3 (Android)';
        final res = await client
            .post(uri, headers: reqHeaders, body: body)
            .timeout(timeout);
        return res;
      } on SocketException catch (e) {
        if (attempts >= maxRetries) {
          throw Exception('网络连接中断 ($e)，请检查网络连接或稍后重试！');
        }
        await Future.delayed(const Duration(milliseconds: 600));
      } on http.ClientException catch (e) {
        if (attempts >= maxRetries) {
          throw Exception('服务器连接中断 (${e.message})，可能由于接口负载或网络抖动，请重试！');
        }
        await Future.delayed(const Duration(milliseconds: 600));
      } catch (e) {
        if (attempts >= maxRetries) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 600));
      } finally {
        client.close();
      }
    }
  }

  /// 调用 AI 分析文本要求或参考图片，并返回生成的 LayoutTemplate
  static Future<LayoutTemplate> generateTemplate({
    required String promptText,
    File? imageFile,
  }) async {
    final baseUrl = await AiServiceConfig.getBaseUrl();
    final apiKey = await AiServiceConfig.getApiKey();
    final model = await AiServiceConfig.getModel();

    if (apiKey.isEmpty) {
      throw Exception('请先在 AI 设置中配置 API Key（如硅基流动或自定义 OpenAI 兼容接口）！');
    }

    var cleanUrl = baseUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final endpoint = cleanUrl.endsWith('/chat/completions')
        ? cleanUrl
        : '$cleanUrl/chat/completions';

    // 针对 HiPDA 论坛排版结构构建专用的系统提示词
    const systemPrompt = '''
你是一个精通网页排版、杂志设计与移动端 UI 视觉的专家。
用户希望为「Hi! PDA 论坛（Discuz 7.2 论坛）转 PDF 导出工具」生成一个专属的排版模板。

论坛页面由多个楼层组成。每个楼层的数据模型划分如下：
1. 用户信息（分为三类）：
   - 头像: avatar
   - 名字: username
   - 剩余其他信息（包含用户等级、在线时间太阳月亮星星、UID、帖子数、积分、注册日期等）: otherInfo
2. 楼层元信息：
   - 楼层序号: floorBadge (如楼主、沙发、#2)
   - 发帖时间: postTime
3. 正文与签名：
   - 正文内容: postText
   - 签名档: signature
4. 排版模式 layoutMode:
   - "card": 现代卡片上下流式（移动卡片风，楼层独立成卡片）
   - "split": 经典论坛左右分栏（左侧作者栏，右侧正文栏）
   - "minimal": 极简纯粹阅读（弱化作者，突出正文文本）
   - "raw": 原汁原味（原汁原味保留论坛经典桌面排版）

请分析用户的需求（文本描述或排版参考图），输出一个严格合法的 JSON 对象，不包含任何 Markdown 格式包裹（不要输出 ```json ... ```）：
{
  "name": "模板名称 (简短有特色)",
  "description": "模板设计说明",
  "defaultWidth": 600,
  "layoutMode": "card", 
  "showAvatar": true,
  "avatarSize": 42,
  "avatarRound": true,
  "avatarBorderColor": "#e5e7eb",
  "showUsername": true,
  "usernameColor": "#111827",
  "usernameBold": true,
  "showOtherInfo": false,
  "otherInfoColor": "#6b7280",
  "showFloorBadge": true,
  "floorColor": "#0369a1",
  "showPostTime": true,
  "postTimeColor": "#6b7280",
  "postTextColor": "#1f2937",
  "postLineHeight": 1.65,
  "showSignature": false,
  "cardBorderColor": "#e5e7eb",
  "showFloorDivider": true,
  "cardBackgroundColor": "#ffffff",
  "customCss": "可选补充 CSS 规则，对 .d2pdf-custom-header, .d2pdf-author-card, .postmessage 等微调"
}
''';

    final actualModel = model.trim();
    final isVision = actualModel.toLowerCase().contains('vl') ||
        actualModel.toLowerCase().contains('vision') ||
        actualModel.toLowerCase().contains('4v') ||
        actualModel.toLowerCase().contains('omni') ||
        actualModel.toLowerCase().contains('gemini') ||
        actualModel.toLowerCase().contains('claude-3') ||
        actualModel.toLowerCase().contains('gpt-4');

    List<Map<String, dynamic>> messages = [];
    messages.add({'role': 'system', 'content': systemPrompt});

    if (imageFile != null && imageFile.existsSync()) {
      if (isVision) {
        final bytes = await imageFile.readAsBytes();
        final base64Image = base64Encode(bytes);
        final mimeType = imageFile.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': promptText.trim().isNotEmpty
                  ? '这是排版参考图，请参考该风格设计模板。用户补充说明：$promptText'
                  : '请根据这张图片的版式、色彩搭配与留白设计，为论坛楼层提炼出最匹配的模板配置。',
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              },
            },
          ],
        });
      } else {
        // 当前模型为纯文本模型，不发送多模态数据块以避免接口报错
        final userText = promptText.trim().isNotEmpty
            ? promptText.trim()
            : '设计一个美观、现代、阅读舒适的论坛 PDF 排版模板。';
        messages.add({
          'role': 'user',
          'content': '$userText\n\n（提示：用户提供了参考排版图片，当前使用模型 $actualModel 为纯文本模型。请结合上述要求及现代高品质排版设计规范生成完整的模板 JSON 配置）',
        });
      }
    } else {
      messages.add({
        'role': 'user',
        'content': promptText.trim().isNotEmpty
            ? promptText
            : '设计一个美观、现代、阅读舒适的论坛 PDF 排版模板。',
      });
    }

    final requestBody = {
      'model': actualModel,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 2000,
    };

    final response = await _postWithRetry(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(requestBody),
      timeout: const Duration(seconds: 90),
    );

    if (response.statusCode != 200) {
      throw Exception('AI 接口返回错误 (${response.statusCode}):\n${response.body}');
    }

    final respJson = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = respJson['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('AI 返回的内容为空！');
    }

    var content = choices[0]['message']?['content']?.toString() ?? '';
    content = content.trim();

    // 清理思考链 <think>...</think> 标签内容
    if (content.contains('</think>')) {
      content = content.substring(content.lastIndexOf('</think>') + 8).trim();
    }

    // 清理 markdown 代码块包裹
    if (content.startsWith('```json')) {
      content = content.substring(7);
    } else if (content.startsWith('```')) {
      content = content.substring(3);
    }
    if (content.endsWith('```')) {
      content = content.substring(0, content.length - 3);
    }
    content = content.trim();

    final int startBrace = content.indexOf('{');
    final int endBrace = content.lastIndexOf('}');
    if (startBrace != -1 && endBrace != -1 && endBrace > startBrace) {
      content = content.substring(startBrace, endBrace + 1);
    }

    final Map<String, dynamic> parsed = jsonDecode(content);
    parsed['id'] = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    parsed['isBuiltin'] = false;

    return LayoutTemplate.fromJson(parsed);
  }

  /// 测试 API 连接与模型可用性
  static Future<String> testConnection({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key！');
    }
    var cleanUrl = baseUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final endpoint = cleanUrl.endsWith('/chat/completions')
        ? cleanUrl
        : '$cleanUrl/chat/completions';

    final requestBody = jsonEncode({
      'model': model.trim(),
      'messages': [
        {
          'role': 'user',
          'content': 'Hi, respond with OK only.',
        }
      ],
      'max_tokens': 16,
      'temperature': 0.1,
    });

    final stopwatch = Stopwatch()..start();
    final response = await _postWithRetry(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: requestBody,
      timeout: const Duration(seconds: 20),
    );
    stopwatch.stop();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = decoded['choices']?[0]?['message']?['content']?.toString().trim() ?? '';
        return '测试成功！响应耗时: ${stopwatch.elapsedMilliseconds}ms\n模型回复: $reply';
      } catch (_) {
        return '测试成功！HTTP ${response.statusCode} (耗时: ${stopwatch.elapsedMilliseconds}ms)';
      }
    } else {
      String errMsg = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded['message'] != null) {
          errMsg += ': ${decoded['message']}';
        } else if (decoded['error'] != null) {
          errMsg += ': ${decoded['error']}';
        }
      } catch (_) {
        errMsg += ': ${response.body}';
      }
      throw Exception(errMsg);
    }
  }
}
