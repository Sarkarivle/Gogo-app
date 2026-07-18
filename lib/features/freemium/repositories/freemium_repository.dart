import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/utils/phone_utils.dart';

class FreemiumRepository {
  static final FreemiumRepository _instance = FreemiumRepository._internal();
  factory FreemiumRepository() => _instance;
  FreemiumRepository._internal();

  /// Notify backend that user started their free trial
  Future<void> logTrialStart(String phone) async {
    try {
      final nPhone = PhoneUtils.normalize(phone) ?? phone;
      await ApiService.post('/api/user/freemium/log-start', {'phone': nPhone});
    } catch (e) {
      // Silent error
    }
  }
}
