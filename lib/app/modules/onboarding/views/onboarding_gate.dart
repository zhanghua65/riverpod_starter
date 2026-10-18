import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/di/rhythm_provider.dart';
import '/app/modules/onboarding/views/onboarding_view.dart';

/// Shows the first-use guide until it has been completed, then [child].
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingProvider);
    return done.when(
      loading: () => const Scaffold(body: SizedBox.shrink()),
      // A store that cannot be read must not lock the user out of the app.
      error: (_, __) => child,
      data: (done) => done
          ? child
          : OnboardingView(
              onFinish: () =>
                  ref.read(onboardingProvider.notifier).setDone(true),
            ),
    );
  }
}
