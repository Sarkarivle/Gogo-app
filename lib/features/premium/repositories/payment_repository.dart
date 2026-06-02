import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';

class PaymentRepository {
  static final PaymentRepository _instance = PaymentRepository._internal();
  factory PaymentRepository() => _instance;
  PaymentRepository._internal();

  // Payment Configuration State
  String _activeGateway = 'razorpay';
  bool _isUpiEnabled = true;
  bool _isGooglePlayEnabled = true;
  int _trialPrice = 1;
  int _monthlyPrice = 199;
  
  DateTime? _lastFetchTime;
  final Duration _cacheTTL = const Duration(minutes: 15);

  // Getters
  String get activeGateway => _activeGateway;
  bool get isUpiEnabled => _isUpiEnabled;
  bool get isGooglePlayEnabled => _isGooglePlayEnabled;
  int get trialPrice => _trialPrice;
  int get monthlyPrice => _monthlyPrice;

  Future<void> fetchPaymentConfigs({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheTTL) {
        return;
      }
    }

    try {
      final response = await ApiService.get('/api/payment/settings');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _activeGateway = data['activeGateway'] ?? 'razorpay';
          
          if (data['config'] != null) {
            _trialPrice = data['config']['trialPrice'] ?? 1;
            _monthlyPrice = data['config']['monthlyPrice'] ?? 199;
            _isUpiEnabled = data['config']['isUpiEnabled'] ?? true;
            _isGooglePlayEnabled = data['config']['isGooglePlayEnabled'] ?? true;
          }
          _lastFetchTime = DateTime.now();
          debugPrint('💳 Payment Repository Synced: Gateway=$_activeGateway, Prices=$_trialPrice/$_monthlyPrice');
        }
      }
    } catch (e) {
      debugPrint('Error fetching payment configs: $e');
    }
  }
}
