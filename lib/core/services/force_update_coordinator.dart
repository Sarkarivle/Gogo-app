import 'package:flutter/material.dart';
import 'package:gogo/main.dart';
import 'package:gogo/shared/widgets/force_update_dialog.dart';
import 'package:gogo/core/services/app_config_service.dart';

class ForceUpdateCoordinator {
  static final ForceUpdateCoordinator _instance = ForceUpdateCoordinator._internal();
  factory ForceUpdateCoordinator() => _instance;
  ForceUpdateCoordinator._internal();

  bool _isModalShowing = false;

  Future<void> checkAndShowUpdate(BuildContext context, {bool forceRefresh = false}) async {
    if (_isModalShowing) return;

    final config = await AppConfigService().fetchAppUpdateConfig(forceRefresh: forceRefresh);
    if (config == null || !config.forceUpdateEnabled) return;

    final isRequired = await AppConfigService().isUpdateRequired();
    if (isRequired) {
      _showUpdateModal(config);
    }
  }

  void _showUpdateModal(AppUpdateConfig config) {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null || _isModalShowing) return;

    _isModalShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (context) => ForceUpdateDialog(config: config),
    ).then((_) {
      _isModalShowing = false;
    });
  }
}
