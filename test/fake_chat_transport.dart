import 'package:riverpod_starter/app/core/services/ai/ai_config.dart';
import 'package:riverpod_starter/app/core/services/ai/chat_client.dart';

/// Answers with canned [replies] in order and records what was sent.
class FakeChatTransport implements ChatTransport {
  FakeChatTransport(this.replies);

  final List<String> replies;
  final requests = <List<ChatMessage>>[];

  @override
  Future<String> complete(AiConfig config, List<ChatMessage> messages) async {
    requests.add(messages);
    if (replies.isEmpty) throw const AiException('no reply left');
    return replies.removeAt(0);
  }
}
