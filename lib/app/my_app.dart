import 'package:flutter/material.dart';
import '/l10n/app_localizations.dart';

import '/app/core/values/app_colors.dart';
import '/app/modules/rhythm/widgets/alarm_ring_listener.dart';
import '/app/routes/app_pages.dart';
import '/flavors/build_config.dart';
import '/flavors/env_config.dart';

class MyApp extends StatelessWidget {
  MyApp({Key? key}) : super(key: key);

  final EnvConfig _envConfig = BuildConfig.instance.config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: _envConfig.appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: _getSupportedLocal(),
      //debugShowCheckedModeBanner: true,
      routerDelegate: AppPages.router.routerDelegate,
      routeInformationParser: AppPages.router.routeInformationParser,
      routeInformationProvider: AppPages.router.routeInformationProvider,
      builder: (context, child) => AlarmRingListener(child: child!),
      theme: ThemeData(
        primarySwatch: AppColors.colorPrimarySwatch,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
        primaryColor: AppColors.colorPrimary,
        textTheme: const TextTheme(
          labelLarge: TextStyle(
            color: Colors.white,
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        fontFamily: 'Roboto',
      ),

      //home: LandingView(),
    );
  }

  List<Locale> _getSupportedLocal() {
    return [
      const Locale('en', ''),
      const Locale('bn', ''),
    ];
  }
}
