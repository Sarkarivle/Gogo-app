import 'dart:convert';
import 'dart:async';
import 'package:gogo/core/api/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupi.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfupipayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

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
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  Future<void> initiatePayment(Map<String, dynamic> data, Function(Map<String, dynamic>) onSuccess, Function(String) onError) async {
    // Priority 1: Use googlePlayId as the target plan
    String? targetBasePlanId = data['googlePlayId']?.toString() ?? data['productId']?.toString();
    
    // Priority 2: Use googlePlaySubId as the parent product
    String? parentProductId = data['googlePlaySubId']?.toString();

    // If parentProductId is missing, we try to use targetBasePlanId as the main product ID
    // (This handles cases where the user only enters one ID in the admin panel)
    String mainSubscriptionId = (parentProductId != null && parentProductId.isNotEmpty) 
        ? parentProductId 
        : (targetBasePlanId ?? 'gogo_monthly_199');
    
    debugPrint("DEBUG: 💳 Google Play Priority -> Search Sub: $mainSubscriptionId, Target Offer/Base: $targetBasePlanId");
    
    try {
      final bool available = await _iap.isAvailable();
      if (!available) {
        onError("Google Play Billing is not available");
        return;
      }

      ProductDetailsResponse response = await _iap.queryProductDetails({mainSubscriptionId});

      if (response.error != null) {
        onError("Play Store Error: ${response.error!.message}");
        return;
      }

      if (response.productDetails.isEmpty) {
        // If the first attempt failed and we had a separate base ID, maybe the base ID IS the product ID
        if (parentProductId != null && parentProductId.isNotEmpty && targetBasePlanId != null) {
           debugPrint("🔍 Retrying with Base ID as Product ID: $targetBasePlanId");
           response = await _iap.queryProductDetails({targetBasePlanId});
           if (response.productDetails.isNotEmpty) {
             mainSubscriptionId = targetBasePlanId;
           }
        }
        
        if (response.productDetails.isEmpty) {
          onError("Plan '$mainSubscriptionId' not found in Play Store. Check Admin Panel.");
          return;
        }
      }

      final ProductDetails productDetails = response.productDetails.first;
      PurchaseParam purchaseParam;

      if (productDetails is GooglePlayProductDetails) {
        String? selectedOfferToken;
        
        final GooglePlayProductDetails googleDetails = productDetails;
        final List<SubscriptionOfferDetailsWrapper> offers = googleDetails.productDetails.subscriptionOfferDetails ?? [];
        
        debugPrint("--------------------------------------------------");
        debugPrint("DEBUG: 📦 Google Play Selection Engine");
        debugPrint("DEBUG: Target ID from Admin: $targetBasePlanId");
        debugPrint("DEBUG: Total Paths Found: ${offers.length}");

        // PRIORITY SELECTION LOGIC
        
        // 1. First Pass: Look for an exact match on OFFER ID (This is the discount/trial)
        for (var o in offers) {
          if (o.offerId != null && o.offerId == targetBasePlanId) {
            selectedOfferToken = o.offerIdToken;
            debugPrint("✅ MATCH: Found exact Offer ID: ${o.offerId}");
            break;
          }
        }

        // 2. Second Pass: If no Offer match, look for Base Plan match and pick its best offer
        if (selectedOfferToken == null) {
          for (var o in offers) {
            if (o.basePlanId == targetBasePlanId) {
              // We prefer an entry with an offerId if available on this base plan
              if (selectedOfferToken == null || o.offerId != null) {
                selectedOfferToken = o.offerIdToken;
                debugPrint("✅ MATCH: Found Base Plan: ${o.basePlanId} (Using Offer: ${o.offerId ?? 'None'})");
                if (o.offerId != null) break; // Found a discounted path for this base plan
              }
            }
          }
        }

        // 3. Last Resort: If still nothing matches, just pick the first discounted offer available
        if (selectedOfferToken == null) {
          for (var o in offers) {
            if (o.offerId != null && o.offerId.toString().isNotEmpty) {
              selectedOfferToken = o.offerIdToken;
              debugPrint("✅ FALLBACK: Using first available Offer: ${o.offerId}");
              break;
            }
          }
        }
        
        // 4. Default: If absolutely nothing matches, use the one it was originally created for
        if (selectedOfferToken == null) {
          selectedOfferToken = googleDetails.offerToken;
          debugPrint("ℹ️ INFO: No custom match found. Using default offerToken.");
        }
        debugPrint("--------------------------------------------------");

        if (selectedOfferToken != null) {
          purchaseParam = GooglePlayPurchaseParam(
            productDetails: productDetails,
            changeSubscriptionParam: null,
            offerToken: selectedOfferToken,
          );
        } else {
          purchaseParam = PurchaseParam(productDetails: productDetails);
        }
      } else {
        purchaseParam = PurchaseParam(productDetails: productDetails);
      }

      await _subscription?.cancel();
      
      _subscription = _iap.purchaseStream.listen((List<PurchaseDetails> purchaseDetailsList) {
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
            _subscription?.cancel();
            _subscription = null;
          } else if (purchase.status == PurchaseStatus.error) {
            onError(purchase.error?.message ?? "Play Store error");
            _subscription?.cancel();
            _subscription = null;
          } else if (purchase.status == PurchaseStatus.canceled) {
            onError("Payment Cancelled");
            _subscription?.cancel();
            _subscription = null;
          }
        }
      }, onError: (e) {
        onError(e.toString());
        _subscription?.cancel();
        _subscription = null;
      });

      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      onError(e.toString());
    }
  }
}

class PaymentService {
  static Future<Map<String, dynamic>> createOrder(String phone, {
    String? gateway,
    int? amount,
    String? offerId,
    String? googlePlayId,
    String? googlePlaySubId,
    int? duration,
    bool isSubscription = false,
  }) async {
    final response = await ApiService.post('/api/payment/create-order', {
      'phone': phone,
      'preferredGateway': gateway,
      if (amount != null) 'amount': amount,
      if (offerId != null) 'offerId': offerId,
      if (googlePlayId != null) 'googlePlayId': googlePlayId,
      if (googlePlaySubId != null) 'googlePlaySubId': googlePlaySubId,
      if (duration != null) 'duration': duration,
      'isSubscription': isSubscription,
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
      default: return GooglePlayHandler();
    }
  }
}
