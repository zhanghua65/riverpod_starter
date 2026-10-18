import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

class ChatMessage {
  const ChatMessage.system(this.content) : role = 'system';
  const ChatMessage.user(this.content) : role = 'user';

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// A request that failed; [message] is shown to the user as is.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends a conversation and returns the assistant's reply.
abstract class ChatTransport {
  Future<String> complete(AiConfig config, List<ChatMessage> messages);
}

/// Calls an OpenAI-compatible `chat/completions` endpoint.
class HttpChatTransport implements ChatTransport {
  HttpChatTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const timeout = Duration(seconds: 60);

  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages) async {
    final endpoint = config.endpoint;
    if (!config.isComplete || endpoint == null) {
      throw const AiException('请先在设置页填写 AI 服务地址、API Key 和模型');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': config.model.trim(),
              'messages': [for (final m in messages) m.toJson()],
              'temperature': 0.3,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AiException('AI 服务响应超时，请稍后再试');
    } on Exception catch (e) {
      throw AiException('连不上 AI 服务：$e');
    }

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiException('API Key 无效或没有权限');
    }
    if (response.statusCode != 200) {
      throw AiException('AI 服务返回错误 ${response.statusCode}：${_errorOf(body)}');
    }

    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choice = (json['choices'] as List).first as Map<String, dynamic>;
      final content = (choice['message'] as Map<String, dynamic>)['content'];
      if (content is String && content.trim().isNotEmpty) return content;
    } on Object {
      // Falls through to the error below.
    }
    throw const AiException('AI 服务返回的内容无法识别，请检查服务地址和模型名');
  }

  static String _errorOf(String body) {
    try {
      final error = (jsonDecode(body) as Map<String, dynamic>)['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } on Object {
      // Not JSON; show the start of the body instead.
    }
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }
}
