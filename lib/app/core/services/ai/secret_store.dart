import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the AI service key lives. Kept apart from the plain preferences so
/// the key is encrypted at rest.
abstract class SecretStore {
  /// The saved key, or an empty string when there is none or it can't be
  /// read.
  Future<String> readApiKey();

  /// Saves [key]; an empty key deletes it.
  Future<void> writeApiKey(String key);
}

/// Android Keystore backed storage.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _apiKey = 'ai.apiKey';

  // A broken keystore (restored backup, ROM quirks) must not break the
  // app: the advisor just reads as not configured.
  @override
  Future<String> readApiKey() async {
    try {
      return await _storage.read(key: _apiKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> writeApiKey(String key) async {
    if (key.isEmpty) {
      await _storage.delete(key: _apiKey);
    } else {
      await _storage.write(key: _apiKey, value: key);
    }
  }
}

/// Keeps the key in memory; the default for tests.
class MemorySecretStore implements SecretStore {
  String _key = '';

  @override
  Future<String> readApiKey() async => _key;

  @override
  Future<void> writeApiKey(String key) async => _key = key;
}
