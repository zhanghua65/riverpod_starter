import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/advisor_provider.dart';
import '/app/core/services/ai/ai_config.dart';
import '/app/core/services/ai/chat_client.dart';

/// The user's own OpenAI-compatible endpoint, key and model.
class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key, required this.config});

  final AiConfig config;

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  late final _baseUrl = TextEditingController(text: widget.config.baseUrl);
  late final _apiKey = TextEditingController(text: widget.config.apiKey);
  late final _model = TextEditingController(text: widget.config.model);
  bool _showKey = false;
  bool _busy = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  AiConfig get _entered => AiConfig(
    baseUrl: _baseUrl.text.trim(),
    apiKey: _apiKey.text.trim(),
    model: _model.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('AI 助手', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '支持任何兼容 OpenAI 接口的服务。用 AI 时会把目标作息、设置、工作作息和最近 14 晚的'
          '计划与实际入睡时间发到你填的地址；Key 只存在本机。不填就不会联网。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextField(
          controller: _baseUrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '服务地址',
            hintText: 'https://api.openai.com/v1',
          ),
        ),
        TextField(
          controller: _apiKey,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: 'API Key',
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
        ),
        TextField(
          controller: _model,
          decoration: const InputDecoration(
            labelText: '模型',
            hintText: '例如 gpt-4o-mini、deepseek-chat',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : _test,
              child: const Text('测试连接'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final config = _entered;
    final messenger = ScaffoldMessenger.of(context);
    if (config != const AiConfig() && !config.isComplete) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请填完整：服务地址需以 http(s):// 开头，Key 和模型不能为空')),
      );
      return;
    }
    await ref.read(aiConfigProvider.notifier).save(config);
    messenger.showSnackBar(
      SnackBar(content: Text(config.isComplete ? '已保存' : '已清空，AI 助手关闭')),
    );
  }

  Future<void> _test() async {
    final config = _entered;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      await ref.read(advisorProvider).testConnection(config);
      message = '连接成功';
    } on AiException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
