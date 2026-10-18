import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '/app/routes/app_routes.dart';
import '/app/modules/landing/views/landing_view.dart';
import '/app/modules/onboarding/views/onboarding_gate.dart';
import '/app/modules/permissions/views/permission_check_view.dart';
import '/app/modules/rhythm/views/history_view.dart';
import '/app/modules/rhythm/views/ring_view.dart';


class AppPages {
  AppPages._();

  static final router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    initialLocation: Paths.LANDING,
    routes: <GoRoute>[
      GoRoute(
          name: Routes.LANDING,
          path: Paths.LANDING,
          builder: (context, state) =>
              OnboardingGate(child: LandingView())),
      GoRoute(
          name: Routes.RING,
          path: Paths.RING,
          builder: (context, state) =>
              RingView(alarm: state.extra! as AlarmSettings)),
      GoRoute(
          name: Routes.PERMISSIONS,
          path: Paths.PERMISSIONS,
          builder: (context, state) => const PermissionCheckView()),
      GoRoute(
          name: Routes.HISTORY,
          path: Paths.HISTORY,
          builder: (context, state) => const HistoryView()),
    ],
  );
}
