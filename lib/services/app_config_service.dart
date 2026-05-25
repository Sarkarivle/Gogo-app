import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'api_service.dart';

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

  Future<AppUpdateConfig?> fetchAppUpdateConfig({bool forceRefresh = false}) async {
    // Check cache
    if (!forceRefresh && _cachedConfig != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheTTL) {
        return _cachedConfig;
      }
    }

    try {
      final response = await ApiService.get('/api/admin/config/app_update_config');

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
    return _cachedConfig; // Return last known good config if fetch fails
  }

  Future<bool> isUpdateRequired() async {
    final config = await fetchAppUpdateConfig();
    if (config == null || !config.forceUpdateEnabled) return false;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    return _compareVersions(currentVersion, config.latestVersion) < 0;
  }

  // Returns:
  // -1 if v1 < v2
  //  0 if v1 == v2
  //  1 if v1 > v2
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
    // Remove any non-numeric suffixes like -alpha, +1 etc.
    final numericVersion = version.split(RegExp(r'[-+]'))[0];
    return numericVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }
}
