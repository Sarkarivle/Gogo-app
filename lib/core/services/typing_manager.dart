import 'package:flutter/foundation.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class TypingManager {
  static final TypingManager _instance = TypingManager._internal();
  factory TypingManager() => _instance;
  TypingManager._internal();

  final Map<String, ValueNotifier<bool>> _notifiers = {};
  final Map<String, String> _normalizedCache = {};

  String _getNormalized(String phone) {
    if (_normalizedCache.containsKey(phone)) return _normalizedCache[phone]!;
    final normalized = PhoneUtils.normalize(phone) ?? phone;
    _normalizedCache[phone] = normalized;
    return normalized;
  }

  ValueNotifier<bool> getTypingNotifier(String? phone) {
    if (phone == null) return ValueNotifier<bool>(false);
    final normalized = _getNormalized(phone);
    if (!_notifiers.containsKey(normalized)) {
      _notifiers[normalized] = ValueNotifier<bool>(false);
    }
    return _notifiers[normalized]!;
  }

  void setTyping(String? phone, bool isTyping) {
    if (phone == null) return;
    final normalized = _getNormalized(phone);
    if (_notifiers.containsKey(normalized)) {
      if (_notifiers[normalized]!.value != isTyping) {
        _notifiers[normalized]!.value = isTyping;
      }
    } else {
      _notifiers[normalized] = ValueNotifier<bool>(isTyping);
    }
  }
}
