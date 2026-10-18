import 'package:alarm/alarm.dart';
import 'package:go_router/go_router.dart';
import '/app/routes/app_routes.dart';
import '/app/modules/landing/views/landing_view.dart';
import '/app/modules/rhythm/views/ring_view.dart';


class AppPages {
  AppPages._();

  static final router = GoRouter(
    debugLogDiagnostics: true,
    initialLocation: Paths.LANDING,
    routes: <GoRoute>[
      GoRoute(
          name: Routes.LANDING,
          path: Paths.LANDING,
          builder: (context, state) => LandingView()),
      GoRoute(
          name: Routes.RING,
          path: Paths.RING,
          builder: (context, state) =>
              RingView(alarm: state.extra! as AlarmSettings)),
    ],
  );
}
