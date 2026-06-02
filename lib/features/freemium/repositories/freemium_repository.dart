import 'package:gogo/core/api/api_service.dart';

class FreemiumRepository {
  static final FreemiumRepository _instance = FreemiumRepository._internal();
  factory FreemiumRepository() => _instance;
  FreemiumRepository._internal();

  /// Notify backend that user started their free trial
  Future<void> logTrialStart(String phone) async {
    try {
      await ApiService.post('/api/user/freemium/log-start', {'phone': phone});
    } catch (e) {
      // Silent error
    }
  }
}
