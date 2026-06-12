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
    if (config == null) return;

    final isRequired = await AppConfigService().isUpdateRequired();
    if (isRequired) {
      _showUpdateModal(config, isForce: true);
      return;
    }

    final isOptional = await AppConfigService().isOptionalUpdateAvailable();
    if (isOptional) {
      _showUpdateModal(config, isForce: false);
    }
  }

  void _showUpdateModal(AppUpdateConfig config, {required bool isForce}) {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null || _isModalShowing) return;

    _isModalShowing = true;
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      useSafeArea: false,
      builder: (context) => ForceUpdateDialog(config: config, isForce: isForce),
    ).then((_) {
      _isModalShowing = false;
    });
  }
}
