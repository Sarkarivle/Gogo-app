import 'package:flutter/foundation.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class PresenceManager {
  static final PresenceManager _instance = PresenceManager._internal();
  factory PresenceManager() => _instance;
  PresenceManager._internal();

  // Map of phone -> ValueNotifier<bool>
  // Isse har user ke paas apna khud ka listener hoga
  final Map<String, ValueNotifier<bool>> _notifiers = {};
  final Map<String, String> _normalizedCache = {};

  String _getNormalized(String phone) {
    if (_normalizedCache.containsKey(phone)) return _normalizedCache[phone]!;
    final normalized = PhoneUtils.normalize(phone) ?? phone;
    _normalizedCache[phone] = normalized;
    return normalized;
  }

  /// Gets a ValueNotifier for a specific user's online status
  ValueNotifier<bool> getStatusNotifier(String? phone, bool initialValue) {
    if (phone == null) return ValueNotifier<bool>(false);
    final normalized = _getNormalized(phone);
    
    if (!_notifiers.containsKey(normalized)) {
      _notifiers[normalized] = ValueNotifier<bool>(initialValue);
    }
    return _notifiers[normalized]!;
  }

  /// Updates status for a specific user
  void updateStatus(String? phone, bool isOnline) {
    if (phone == null) return;
    final normalized = _getNormalized(phone);
    
    if (_notifiers.containsKey(normalized)) {
      if (_notifiers[normalized]!.value != isOnline) {
        _notifiers[normalized]!.value = isOnline;
      }
    } else {
      _notifiers[normalized] = ValueNotifier<bool>(isOnline);
    }
  }

  /// Checks if a user is online without creating a notifier
  bool isOnline(String? phone) {
    if (phone == null) return false;
    final normalized = _getNormalized(phone);
    return _notifiers[normalized]?.value ?? false;
  }

  /// Bulk update from initial server data
  void bulkUpdate(Map<String, bool> onlineMap) {
    onlineMap.forEach((phone, status) {
      updateStatus(phone, status);
    });
  }
}
