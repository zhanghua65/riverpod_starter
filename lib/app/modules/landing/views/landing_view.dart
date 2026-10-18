import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/app/core/base/base_view.dart';
import '/app/core/di/controller_provider.dart';
import '/app/modules/favourite/views/favourite_view.dart';
import '/app/modules/home/views/home_view.dart';
import '/app/modules/landing/controllers/landing_controller.dart';
import '/app/modules/landing/ui_model/menu_code.dart';
import '/app/modules/landing/views/bottom_nav_bar.dart';
import '/app/modules/rhythm/views/rhythm_view.dart';
import '/app/modules/settings/views/settings_view.dart';

//ignore: must_be_immutable
class LandingView extends BaseView<LandingController> {
  LandingView({Key? key}) : super(key: key);

  @override
  PreferredSizeWidget? appBar(BuildContext context) {
    return null;
  }

  @override
  Widget body(BuildContext context) {
    return Container(
      key: UniqueKey(),
      child: Consumer(
        builder: (context, ref, _) {
          final MenuCode selectedMenu = ref.watch(controller).bottomNavSelectedMenu;

          return _getPageOnSelectedMenu(selectedMenu);
        },
      ),
    );
  }

  @override
  Widget? bottomNavigationBar() {
    return Consumer(builder: (context, ref, _) {
      return BottomNavBar(
        onNewMenuSelected: (MenuCode menuCode) {
          ref.read(controller).onMenuSelected(menuCode);
        },
      );
    });
  }

  final HomeView homeView = HomeView();
  FavouriteView? favoriteView;
  SettingsView? settingsView;

  Widget _getPageOnSelectedMenu(MenuCode menuCode) {
    switch (menuCode) {
      case MenuCode.RHYTHM:
        return const RhythmView();
      case MenuCode.HOME:
        return homeView;
      case MenuCode.FAVORITE:
        favoriteView ??= FavouriteView();
        return favoriteView!;
      case MenuCode.SETTINGS:
        settingsView ??= SettingsView();
        return settingsView!;
    }
  }

  @override
  ProviderBase<LandingController> get controller => landingControllerProvider;
}
