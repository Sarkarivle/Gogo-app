import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupi.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupipayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';

abstract class PaymentHandler {
  Future<void> initiatePayment(
    Map<String, dynamic> orderData, 
    void Function(Map<String, dynamic>) onSuccess, 
    void Function(String) onError,
  );
}

class RazorpayHandler implements PaymentHandler {
  final Razorpay _razorpay = Razorpay();

  @override
  Future<void> initiatePayment(
    Map<String, dynamic> data, 
    void Function(Map<String, dynamic>) onSuccess, 
    void Function(String) onError,
  ) async {
    final subId = data['subscription']?['id'] ?? data['orderId'];
    final rzpKey = data['keyId'];
    
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse res) {
      onSuccess({
        'paymentId': res.paymentId,
        'orderId': res.orderId ?? subId,
        'signature': res.signature,
        'razorpay_subscription_id': subId,
      });
    });
    
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse res) {
      onError(res.message ?? "Payment Failed");
    });
    
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse res) {
      onError("External wallet not supported");
    });
    
    var options = {
      'key': rzpKey,
      if (data['subscription'] != null) 'subscription_id': subId else 'order_id': subId,
      'name': 'GoGo Premium',
      'description': 'Premium Subscription Activation',
      'prefill': {
        'contact': data['phone'],
        'email': '${data['phone']}@gogoapp.com'
      },
      'theme': {'color': '#FFD700'}
    };
    
    try {
      _razorpay.open(options);
    } catch (e) {
      onError("Could not open Razorpay: $e");
    }
  }
}

class PhonePeHandler implements PaymentHandler {
  @override
  Future<void> initiatePayment(Map<String, dynamic> data, Function(Map<String, dynamic>) onSuccess, Function(String) onError) async {
    try {
      String merchantId = data['merchantId'];
      String orderId = data['orderId'];
      String env = data['env'] ?? "UAT";

      String sdkEnv = (env == "UAT" || env == "SANDBOX") ? "SANDBOX" : "PRODUCTION";
      await PhonePePaymentSdk.init(sdkEnv, merchantId.trim(), "GOGO_FLOW", true);

      Map<String, dynamic> requestData = {
        "merchantId": merchantId,
        "orderId": orderId,
        "request": data['base64Payload'],
        "checksum": data['checksum']
      };
      
      var result = await PhonePePaymentSdk.startTransaction(jsonEncode(requestData), "gogoapp");
      if (result != null && result['status'] == 'SUCCESS') {
        onSuccess({'paymentId': orderId});
      } else {
        onError(result?['error'] ?? "Payment Cancelled");
      }
    } catch (e) {
      onError(e.toString());
    }
  }
}

class CashfreeHandler implements PaymentHandler {
  final cfPaymentGatewayService = CFPaymentGatewayService();

  @override
  Future<void> initiatePayment(Map<String, dynamic> data, Function(Map<String, dynamic>) onSuccess, Function(String) onError) async {
    try {
      String orderId = data['orderId'];
      String orderSessionId = data['order_session_id'];
      String env = data['env'] ?? "SANDBOX";

      var session = CFSessionBuilder()
          .setEnvironment(env == "PROD" ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX)
          .setOrderId(orderId)
          .setPaymentSessionId(orderSessionId)
          .build();

      var upi = CFUPIBuilder().setChannel(CFUPIChannel.INTENT).build();
      var payment = CFUPIPaymentBuilder().setSession(session!).setUPI(upi).build();

      cfPaymentGatewayService.setCallback((String id) => onSuccess({'paymentId': id}), (CFErrorResponse err, String id) => onError(err.getMessage() ?? "Failed"));
      cfPaymentGatewayService.doPayment(payment);
    } catch (e) {
      onError(e.toString());
    }
  }
}

class PaymentService {
  static Future<Map<String, dynamic>> createOrder(String phone) async {
    final response = await http.post(
      Uri.parse('http://72.61.170.181:5000/api/payment/create-order'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> verifyPayment(String phone, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('http://72.61.170.181:5000/api/payment/verify-payment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...data, 'phone': phone}),
    );
    return jsonDecode(response.body);
  }

  static PaymentHandler getHandler(String gateway) {
    switch (gateway.toLowerCase()) {
      case 'razorpay': return RazorpayHandler();
      case 'phonepe': return PhonePeHandler();
      case 'cashfree': return CashfreeHandler();
      default: return RazorpayHandler();
    }
  }
}
