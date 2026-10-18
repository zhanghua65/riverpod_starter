import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/modules/landing/controllers/landing_controller.dart';

final landingControllerProvider = ChangeNotifierProvider<LandingController>(
  (ref) => LandingController(ref: ref),
);
