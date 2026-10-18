import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '/flavors/build_config.dart';

/// Logs provider updates and failures in debug builds. Values are left out:
/// printing a whole alarm set or sleep log on every change made the app
/// stutter.
class ProviderLogger extends ProviderObserver {
  final Logger logger = BuildConfig.instance.config.logger;

  String _name(ProviderBase provider) =>
      provider.name ?? provider.runtimeType.toString();

  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    logger.d('provider_updated: ${_name(provider)}');
  }

  @override
  void providerDidFail(
    ProviderBase provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    logger.e(
      'provider_failed: ${_name(provider)}',
      error: error,
      stackTrace: stackTrace,
    );
    super.providerDidFail(provider, error, stackTrace, container);
  }
}
