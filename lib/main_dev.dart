import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/utils/provider_logger.dart';

import '/app/core/services/alarm/alarm_service.dart';
import '/app/core/services/alarm/recall_notifier.dart';
import '/app/my_app.dart';
import '/flavors/build_config.dart';
import '/flavors/env_config.dart';
import '/flavors/environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmService.init();
  await RecallNotifier.init();

  EnvConfig devConfig = EnvConfig(
    appName: "早一点点 Dev",
    shouldCollectCrashLog: true,
  );

  BuildConfig.instantiate(
    envType: Environment.DEVELOPMENT,
    envConfig: devConfig,
  );

  runApp(
    ProviderScope(
      observers: [if (kDebugMode) ProviderLogger()],
      child: MyApp(),
    ),
  );
}
