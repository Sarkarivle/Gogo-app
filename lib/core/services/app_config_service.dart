import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gogo/core/api/api_service.dart';

class AppUpdateConfig {
  final String latestVersion;
  final bool forceUpdateEnabled;
  final String updateTitle;
  final String updateMessage;
  final String playStoreUrl;
  final String minimumSupportedVersion;

  AppUpdateConfig({
    required this.latestVersion,
    required this.forceUpdateEnabled,
    required this.updateTitle,
    required this.updateMessage,
    required this.playStoreUrl,
    required this.minimumSupportedVersion,
  });

  factory AppUpdateConfig.fromJson(Map<String, dynamic> json) {
    return AppUpdateConfig(
      latestVersion: json['latest_version'] ?? '1.0.0',
      forceUpdateEnabled: json['force_update_enabled'] ?? false,
      updateTitle: json['update_title'] ?? 'New Update Available',
      updateMessage: json['update_message'] ?? 'We have improved performance, security, and calling experience.',
      playStoreUrl: json['playstore_url'] ?? '',
      minimumSupportedVersion: json['minimum_supported_version'] ?? '1.0.0',
    );
  }
}

class AppConfigService {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  AppUpdateConfig? _cachedConfig;
  DateTime? _lastFetchTime;
  final Duration _cacheTTL = const Duration(minutes: 15);

  // New Compliance Config with Notifiers for Real-time UI updates
  final ValueNotifier<bool> isStandardModeNotifier = ValueNotifier<bool>(false);
  bool get isStandardMode => isStandardModeNotifier.value;

  final ValueNotifier<bool> isOneMessageTrialEnabledNotifier = ValueNotifier<bool>(false);
  bool get isOneMessageTrialEnabled => isOneMessageTrialEnabledNotifier.value;

  final ValueNotifier<bool> isScreenshotDisabledNotifier = ValueNotifier<bool>(true);
  bool get isScreenshotDisabled => isScreenshotDisabledNotifier.value;

  static const _channel = MethodChannel('com.gogo.app/phone_hint');

  Future<void> _updateNativeSecureMode(bool enabled) async {
    try {
      await _channel.invokeMethod('toggleSecureMode', {'enabled': enabled});
    } catch (e) {
      debugPrint('Error updating native secure mode: $e');
    }
  }

  // New Freemium Configs with Notifiers for Real-time UI updates
  final ValueNotifier<bool> isFreemiumActiveNotifier = ValueNotifier<bool>(false);
  bool get isFreemiumActive => isFreemiumActiveNotifier.value;

  int _freemiumDurationDays = 1;
  int get freemiumDurationDays => _freemiumDurationDays;

  Map<String, dynamic>? _trackingConfig;
  Map<String, dynamic>? get trackingConfig => _trackingConfig;
  DateTime? _lastConfigFetchTime;

  String? get loginImageUrl => _trackingConfig?['loginImageUrl'];

  Future<void> fetchReviewMode({bool forceRefresh = false}) async {
    // Sensitive flags (Freemium/Compliance) should bypass cache if forceRefresh is true
    if (!forceRefresh && _lastConfigFetchTime != null) {
      if (DateTime.now().difference(_lastConfigFetchTime!) < const Duration(minutes: 5)) {
        return;
      }
    }
    
    // If forceRefresh is true, we proceed regardless of time
    try {
      final responses = await Future.wait([
        ApiService.get('/api/payment/settings'),
        ApiService.get('/api/user/tracking-config')
      ]);

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        
        // Update Notifiers ONLY if values changed to prevent junk rebuilds
        final bool newStandardMode = data['isStandardMode'] ?? false;
        if (isStandardModeNotifier.value != newStandardMode) {
          isStandardModeNotifier.value = newStandardMode;
        }

        final bool newOneMessageTrial = data['isOneMessageTrialEnabled'] ?? false;
        if (isOneMessageTrialEnabledNotifier.value != newOneMessageTrial) {
          isOneMessageTrialEnabledNotifier.value = newOneMessageTrial;
        }

        final bool newScreenshotDisabled = data['isScreenshotDisabled'] ?? true;
        if (isScreenshotDisabledNotifier.value != newScreenshotDisabled) {
          isScreenshotDisabledNotifier.value = newScreenshotDisabled;
          _updateNativeSecureMode(newScreenshotDisabled);
        }

        final bool newFreemiumMode = data['isFreemiumActive'] ?? data['isStandardMode'] ?? false;
        if (isFreemiumActiveNotifier.value != newFreemiumMode) {
          isFreemiumActiveNotifier.value = newFreemiumMode;
        }

        _freemiumDurationDays = data['trialDurationDays'] ?? 1;
      }

      if (responses[1].statusCode == 200) {
        final data = jsonDecode(responses[1].body);
        if (data['success'] == true) {
          _trackingConfig = data['config'];
        }
      }
      _lastConfigFetchTime = DateTime.now();
    } catch (e) {
      debugPrint('Error fetching app config: $e');
    }
  }

  Future<AppUpdateConfig?> fetchAppUpdateConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheTTL) {
        return _cachedConfig;
      }
    }

    try {
      final response = await ApiService.get('/api/user/config/app_update_config');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _cachedConfig = AppUpdateConfig.fromJson(data['config']);
          _lastFetchTime = DateTime.now();
          return _cachedConfig;
        }
      }
    } catch (e) {
      debugPrint('Error fetching app update config: $e');
    }
    return _cachedConfig;
  }

  Future<bool> isUpdateRequired() async {
    final config = await fetchAppUpdateConfig();
    if (config == null || !config.forceUpdateEnabled) return false;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    return _compareVersions(currentVersion, config.latestVersion) < 0;
  }

  int _compareVersions(String v1, String v2) {
    try {
      List<int> v1Parts = _extractVersionParts(v1);
      List<int> v2Parts = _extractVersionParts(v2);

      int length = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;

      for (int i = 0; i < length; i++) {
        int p1 = i < v1Parts.length ? v1Parts[i] : 0;
        int p2 = i < v2Parts.length ? v2Parts[i] : 0;

        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }
    } catch (e) {
      debugPrint('Version comparison error: $e');
    }
    return 0;
  }

  List<int> _extractVersionParts(String version) {
    final numericVersion = version.split(RegExp(r'[-+]'))[0];
    return numericVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }
}
