import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_starter/app/core/services/ai/ai_config.dart';
import 'package:riverpod_starter/app/core/services/ai/chat_client.dart';

void main() {
  const config = AiConfig(
    baseUrl: 'https://api.example.com/v1/',
    apiKey: ' sk-test ',
    model: 'some-model',
  );
  const messages = [ChatMessage.system('s'), ChatMessage.user('u')];

  group('endpoint', () {
    test('appends chat/completions to a base url', () {
      expect(
        config.endpoint.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        const AiConfig(
          baseUrl: 'http://192.168.1.2:8080/v1/chat/completions',
        ).endpoint.toString(),
        'http://192.168.1.2:8080/v1/chat/completions',
      );
    });

    test('is null for something that is not a web address', () {
      expect(const AiConfig(baseUrl: 'api.example.com').endpoint, isNull);
      expect(const AiConfig().endpoint, isNull);
      expect(const AiConfig(apiKey: 'k', model: 'm').isComplete, isFalse);
    });

    test('round-trips through json', () {
      expect(AiConfig.fromJson(config.toJson()), config);
      expect(AiConfig.fromJson({'apiKey': 3}), const AiConfig());
    });
  });

  test('posts an OpenAI-style request and returns the reply', () async {
    late http.Request sent;
    final transport = HttpChatTransport(
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': '好的'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    expect(await transport.complete(config, messages), '好的');
    expect(sent.url.toString(), 'https://api.example.com/v1/chat/completions');
    expect(sent.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'some-model');
    expect(body['messages'], [
      {'role': 'system', 'content': 's'},
      {'role': 'user', 'content': 'u'},
    ]);
  });

  Future<String> failWith(http.Response response) => HttpChatTransport(
    client: MockClient((_) async => response),
  ).complete(config, messages);

  test('a rejected key is reported as such', () {
    expect(
      failWith(http.Response('{}', 401)),
      throwsA(
        isA<AiException>().having((e) => e.message, 'message', contains('Key')),
      ),
    );
  });

  test('other errors show the service message', () {
    expect(
      failWith(http.Response('{"error": {"message": "model not found"}}', 404)),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('model not found'),
        ),
      ),
    );
  });

  test('an unexpected body is an error', () {
    expect(
      failWith(http.Response('<html></html>', 200)),
      throwsA(isA<AiException>()),
    );
  });

  test('an incomplete config is refused before any request', () {
    expect(
      HttpChatTransport(
        client: MockClient((_) => fail('no request expected')),
      ).complete(const AiConfig(), messages),
      throwsA(isA<AiException>()),
    );
  });
}
