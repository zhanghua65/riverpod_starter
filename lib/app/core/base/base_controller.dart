import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '/flavors/build_config.dart';
import '/app/core/ui_model/page_state.dart';

abstract class BaseController extends ChangeNotifier {
  final Logger logger = BuildConfig.instance.config.logger;
  final Ref<ChangeNotifier>  ref;

  BaseController({required this.ref}) {
    onInit();
  }

  /// Shows user specific message on the screen
  String _messageController = "";
  String get message => _messageController;
  void showMessage(String msg) {
    _messageController = msg;
    notifyListeners();
  }

  /// Shows user specific error message on the screen
  String _errorMessageController = "";
  String get errorMessage => _errorMessageController;
  void showErrorMessage(String msg) {
    _errorMessageController = msg;
    notifyListeners();
  }


  /// shows user specific success message on the screen
  String _successMessageController = "";
  String get successMessage => _successMessageController;
  void showSuccessMessage(String msg) {
    _successMessageController = msg;
    notifyListeners();
  }

  /// Defines page state of a particular screen
  PageState _pageStateController = PageState.DEFAULT;
  PageState get pageState => _pageStateController;
  void updatePageState(PageState state) {
    _pageStateController = state;
    notifyListeners();
  }

  void resetPageState(){
    _pageStateController = PageState.DEFAULT;
    notifyListeners();
  }
  void showPageLoading(){
    _pageStateController = PageState.LOADING;
    notifyListeners();
  }
  void hideLoading() => resetPageState();

  void resetPageMessage(){
    _messageController = "";
    _errorMessageController = "";
    _successMessageController = "";
  }


  @mustCallSuper
  //ignore: no-empty-block
  void onInit() {}

  @mustCallSuper
  //ignore: no-empty-block
  void onDispose() {
    ref.invalidateSelf();
  }

  @override
  void dispose() {
    onDispose();
    super.dispose();
  }
}
