import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/core/services/ai/ai_config.dart';
import '/app/core/services/ai/chat_client.dart';
import '/app/core/services/ai/rhythm_advisor.dart';
import '/app/core/services/schedule/recovery.dart';
import '/app/core/services/schedule/rhythm_store.dart';

/// Overridden in tests so nothing goes over the network.
final chatTransportProvider = Provider<ChatTransport>(
  (ref) => HttpChatTransport(),
);

final aiConfigProvider = AsyncNotifierProvider<AiConfigController, AiConfig>(
  AiConfigController.new,
);

class AiConfigController extends AsyncNotifier<AiConfig> {
  @override
  Future<AiConfig> build() async =>
      (await ref.watch(rhythmStoreProvider.future)).loadAiConfig();

  Future<void> save(AiConfig config) async {
    await (await ref.read(rhythmStoreProvider.future)).saveAiConfig(config);
    state = AsyncData(config);
  }
}

final advisorProvider = Provider<AdvisorController>(AdvisorController.new);

/// Asks the AI advisor for suggestions. Nothing changes until the user
/// accepts one through [RhythmController].
class AdvisorController {
  AdvisorController(this._ref);

  final Ref _ref;

  /// How often the home page offers a review.
  static const reviewEvery = Duration(days: 7);

  /// Fewer logged nights than this are not worth reviewing.
  static const minNightsToReview = 3;

  Future<ReviewSuggestion> review() async =>
      (await _advisor()).review(await _context());

  Future<TemporaryAdjustment> adjust(String request) async =>
      (await _advisor()).adjust(await _context(), request);

  /// Sends a tiny request to check the endpoint, key and model.
  Future<void> testConnection(AiConfig config) => _ref
      .read(chatTransportProvider)
      .complete(config, const [ChatMessage.user('请只回复：OK')]);

  Future<RhythmAdvisor> _advisor() async {
    final config = await _ref.read(aiConfigProvider.future);
    if (!config.isComplete) {
      throw const AiException('请先在设置页填写 AI 服务地址、API Key 和模型');
    }
    return RhythmAdvisor(
      transport: _ref.read(chatTransportProvider),
      config: config,
    );
  }

  Future<AdvisorContext> _context() async {
    final state = await _ref.read(rhythmControllerProvider.future);
    final plan = state.plan;
    if (plan == null) throw const AiException('请先设定作息计划');
    return AdvisorContext(
      now: DateTime.now(),
      plan: plan,
      work: state.work,
      log: state.log,
    );
  }
}

final reviewedAtProvider =
    AsyncNotifierProvider<ReviewedAtController, DateTime?>(
      ReviewedAtController.new,
    );

/// When the user last applied or dismissed a weekly review.
class ReviewedAtController extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async =>
      (await ref.watch(rhythmStoreProvider.future)).reviewedAt;

  Future<void> markReviewed() async {
    final now = DateTime.now();
    await (await ref.read(rhythmStoreProvider.future)).setReviewedAt(now);
    state = AsyncData(now);
  }
}

final comfortProvider = AsyncNotifierProvider<ComfortController, Comfort?>(
  ComfortController.new,
);

/// The advisor's kind words after a late night, shown on the home page.
class ComfortController extends AsyncNotifier<Comfort?> {
  @override
  Future<Comfort?> build() async =>
      (await ref.watch(rhythmStoreProvider.future)).loadComfort();

  /// Fetches comfort for [night] when [recovery] was late and the AI is set
  /// up. Best effort: failures are only logged.
  Future<void> requestFor(DateTime night, Recovery recovery) async {
    if (!recovery.isLate) return;
    final config = await ref.read(aiConfigProvider.future);
    if (!config.isComplete) return;
    try {
      final rhythm = await ref.read(rhythmControllerProvider.future);
      final plan = rhythm.plan;
      if (plan == null) return;
      final text =
          await RhythmAdvisor(
            transport: ref.read(chatTransportProvider),
            config: config,
          ).comfort(
            AdvisorContext(
              now: DateTime.now(),
              plan: plan,
              work: rhythm.work,
              log: rhythm.log,
            ),
            recovery,
          );
      final comfort = Comfort(night: night, text: text);
      await (await ref.read(rhythmStoreProvider.future)).saveComfort(comfort);
      state = AsyncData(comfort);
    } on AiException catch (e) {
      debugPrint('AI comfort failed: $e');
    }
  }

  Future<void> dismiss() async {
    await (await ref.read(rhythmStoreProvider.future)).saveComfort(null);
    state = const AsyncData(null);
  }
}
