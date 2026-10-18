/// Where the AI advisor sends its requests: any OpenAI-compatible
/// `chat/completions` endpoint, with the user's own key. Stored only on the
/// device.
class AiConfig {
  const AiConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  /// e.g. `https://api.openai.com/v1`; a full `.../chat/completions` URL is
  /// accepted too.
  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isComplete =>
      endpoint != null && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// The chat completions URL, or null when [baseUrl] is not an http(s) URL.
  Uri? get endpoint {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/chat/completions')) url = '$url/chat/completions';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return uri.host.isEmpty ? null : uri;
  }

  Map<String, Object> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    return AiConfig(
      baseUrl: text('baseUrl'),
      apiKey: text('apiKey'),
      model: text('model'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, model);
}
