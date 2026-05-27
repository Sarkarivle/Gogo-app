import 'dart:convert';
import 'api_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupi.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupipayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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
        'gateway': 'razorpay'
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
        onSuccess({'paymentId': orderId, 'gateway': 'phonepe'});
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
      var payment = CFUPIPaymentBuilder().setSession(session).setUPI(upi).build();

      cfPaymentGatewayService.setCallback((String id) => onSuccess({'paymentId': id, 'gateway': 'cashfree'}), (CFErrorResponse err, String id) => onError(err.getMessage() ?? "Failed"));
      cfPaymentGatewayService.doPayment(payment);
    } catch (e) {
      onError(e.toString());
    }
  }
}

class GooglePlayHandler implements PaymentHandler {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Future<void> initiatePayment(Map<String, dynamic> data, Function(Map<String, dynamic>) onSuccess, Function(String) onError) async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      onError("Google Play Billing is not available on this device");
      return;
    }

    final String productId = data['productId'] ?? 'premium_subscription_monthly';
    final Set<String> ids = {productId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      onError(response.error!.message);
      return;
    }

    if (response.productDetails.isEmpty) {
      onError("Subscription plan not found in Play Store");
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

    _iap.purchaseStream.listen((List<PurchaseDetails> purchaseDetailsList) {
      for (var purchase in purchaseDetailsList) {
        if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          onSuccess({
            'gateway': 'google_play',
            'purchaseToken': purchase.verificationData.serverVerificationData,
            'productId': purchase.productID,
            'orderId': purchase.purchaseID,
          });
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
        } else if (purchase.status == PurchaseStatus.error) {
          onError(purchase.error?.message ?? "Play Store error");
        }
      }
    });

    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }
}

class PaymentService {
  static Future<Map<String, dynamic>> createOrder(String phone, {String? gateway}) async {
    final response = await ApiService.post('/api/payment/create-order', {
      'phone': phone,
      'preferredGateway': gateway,
    });
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> verifyPayment(String phone, Map<String, dynamic> data) async {
    final response = await ApiService.post('/api/payment/verify-payment', {...data, 'phone': phone});
    return jsonDecode(response.body);
  }

  static PaymentHandler getHandler(String gateway) {
    switch (gateway.toLowerCase()) {
      case 'razorpay': return RazorpayHandler();
      case 'phonepe': return PhonePeHandler();
      case 'cashfree': return CashfreeHandler();
      case 'google_play': return GooglePlayHandler();
      default: return RazorpayHandler();
    }
  }
}
