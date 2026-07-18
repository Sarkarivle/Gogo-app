import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/features/premium/providers/premium_service.dart';
import 'package:gogo/core/services/ad_service.dart';
import 'package:gogo/shared/screens/offer_trial_screen.dart';
import 'package:gogo/features/profile/repositories/user_repository.dart';

/// Defines the monetization strategy for the user.
enum MonetizationMode { 
  /// Standard mode focusing on direct premium purchases (Google Play/UPI).
  payer, 
  
  /// Alternative mode for users without payment apps, focusing on ad-revenue and rewards.
  adDriven 
}

/// Dynamic Monetization Orchestrator
/// 
/// Enterprise-grade service that intelligently decides the app's monetization avatar
/// based on device capabilities (UPI presence) and backend configuration.
class MonetizationOrchestrator {
  static final MonetizationOrchestrator _instance = MonetizationOrchestrator._internal();
  factory MonetizationOrchestrator() => _instance;
  MonetizationOrchestrator._internal();

  MonetizationMode _currentMode = MonetizationMode.payer;
  bool _isInitialized = false;
  DateTime? _rewardExpiry;

  /// Current monetization mode determined during initialization.
  MonetizationMode get currentMode => _currentMode;

  /// Returns true if the user has active temporary premium access from a rewarded ad.
  bool get hasTemporaryAccess {
    if (_rewardExpiry == null) return false;
    return DateTime.now().isBefore(_rewardExpiry!);
  }

  /// Returns the remaining time of temporary access in a formatted string.
  String get remainingTime {
    if (!hasTemporaryAccess) return "00:00";
    final diff = _rewardExpiry!.difference(DateTime.now());
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  /// Returns true if the app should operate in Ad-Driven mode.
  /// Conditions: No payment apps, Not a premium user, and Master Ads Switch is ON.
  bool get isAdModeActive {
    // Priority 1: Premium status (Paid or Temp) overrides everything.
    if (PremiumService().isPremium || hasTemporaryAccess) return false;
    
    // Priority 2: Master Switch from Backend.
    if (!AppConfigService().isAdsEnabled) return false;
    
    // Priority 3: Device Capability.
    return _currentMode == MonetizationMode.adDriven;
  }

  /// Initialized during Splash Screen.
  /// Detects the presence of UPI apps using generic intent schemes.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load saved expiry
      final expiryMs = prefs.getInt('reward_expiry_timestamp');
      if (expiryMs != null) {
        _rewardExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      }

      // Generic UPI Intent check (India specific protocol)
      final Uri upiUri = Uri.parse('upi://pay');
      bool hasUPI = await canLaunchUrl(upiUri);

      // Decision Logic: 
      // If NO UPI found AND Ads are enabled globally -> AD_DRIVEN
      if (!hasUPI && AppConfigService().isAdsEnabled) {
        _currentMode = MonetizationMode.adDriven;
      } else {
        _currentMode = MonetizationMode.payer;
      }
    } catch (e) {
      debugPrint('MonetizationOrchestrator Init Error: $e');
      _currentMode = MonetizationMode.payer; // Safe Fallback
    }

    _isInitialized = true;
  }

  /// Syncs the detected monetization mode with the backend
  Future<void> syncWithServer(String phone) async {
    try {
      final modeString = _currentMode == MonetizationMode.adDriven ? 'adDriven' : 'payer';
      await ApiService.post('/api/user/update-profile', {
        'monetizationMode': modeString
      });
      debugPrint('✅ Monetization Mode Synced: $modeString');
    } catch (e) {
      debugPrint('❌ Monetization Mode Sync Failed: $e');
    }
  }

  /// Grants dynamic premium access after a rewarded ad based on backend config.
  Future<void> grantDynamicAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final durationMinutes = AppConfigService().rewardDurationMinutes;
    
    _rewardExpiry = DateTime.now().add(Duration(minutes: durationMinutes));
    await prefs.setInt('reward_expiry_timestamp', _rewardExpiry!.millisecondsSinceEpoch);
    
    // Update daily count
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastDate = prefs.getString('reward_last_date') ?? '';
    int count = (lastDate == today) ? (prefs.getInt('reward_daily_count') ?? 0) : 0;
    
    await prefs.setString('reward_last_date', today);
    await prefs.setInt('reward_daily_count', count + 1);

    // Notify server about temporary premium status (Green in Admin)
    try {
      await ApiService.post('/api/user/update-premium', {
        'isPremium': true,
        'duration': durationMinutes,
        'monetizationMode': 'adDriven'
      });
    } catch (e) {
      debugPrint("Error notifying server of reward: $e");
    }
    
    // Trigger global UI refresh
    PremiumService().refreshAccessState();
  }

  /// Checks if user has reached daily limit for rewarded ads
  Future<bool> canUserWatchRewardedAd() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastDate = prefs.getString('reward_last_date') ?? '';
    
    if (lastDate != today) return true;
    
    final count = prefs.getInt('reward_daily_count') ?? 0;
    final limit = AppConfigService().rewardDailyLimit;
    
    return count < limit;
  }

  /// Master Interceptor for Chat/Feature Limits
  void showChoicePopup(BuildContext context) {
    // 1. Respect the current mode: Payer users get the payment screen, Ad-Driven get rewards.
    if (!isAdModeActive) {
      OfferTrialScreen.show(context);
      return;
    }

    // 2. AD-DRIVEN LOGIC:
    // Notify server immediately that this user is now in Ad-Driven segment (Red in Admin)
    final user = UserRepository().currentUser;
    if (user != null) {
      syncWithServer(user['phone']);
    }

    // 3. Show the Professional Hinglish Centered Dialog
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _buildCenteredChoiceDialog(context),
    );
  }

  Widget _buildCenteredChoiceDialog(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 30, spreadRadius: 10)
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Close (Cut) Button - Premium Style
            Positioned(
              right: -12,
              top: -12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                ),
              ),
            ),
            
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 15),
                // Premium Icon with Glow
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.amber.withValues(alpha: 0.05), blurRadius: 20, spreadRadius: 5)
                    ],
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 45),
                ),
                const SizedBox(height: 24),
                
                // Headline Hinglish
                const Text(
                  "Limit Khatam Ho Gayi! ✋",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
                ),
                const SizedBox(height: 12),
                
                // Body Text
                Text(
                  "Par fikr na karein! Ek chota video dekh kar aap ${AppConfigService().rewardDurationMinutes} minutes ke liye saare Premium features FREE unlock kar sakte hain.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 35),
                
                // Primary Action: Watch Ad
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (!await canUserWatchRewardedAd()) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Aaj ki limit khatam ho gayi hai. Kal fir try karein!"),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                        return;
                      }
                      
                      // Show loading overlay if ad not ready
                      if (!AdService().isRewardedAdLoaded()) {
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
                          );
                        }
                        
                        AdService().loadRewardedAd();
                        
                        // Wait up to 8 seconds for real production ads
                        int attempts = 0;
                        while (!AdService().isRewardedAdLoaded() && attempts < 16) {
                          await Future.delayed(const Duration(milliseconds: 500));
                          attempts++;
                        }

                        if (context.mounted) Navigator.pop(context); // Remove loader
                      }

                      if (context.mounted) {
                        if (AdService().isRewardedAdLoaded()) {
                          Navigator.pop(context); // Pop choice dialog
                          AdService().showRewardedAd(
                            onRewardEarned: (reward) {
                              grantDynamicAccess();
                              if (context.mounted) {
                                _showRewardGrantedPopup(context);
                              }
                            },
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Ads abhi ready nahi hain. Ek baar internet check karein ya 5 sec baad try karein."))
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.play_circle_filled_rounded, size: 24),
                    label: const Text("Watch Video Ad", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent.shade400,
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shadowColor: Colors.pinkAccent.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
                
                const SizedBox(height: 28),
                
                // Small Line for Premium Upsell
                const Text(
                  "Ad nahi dekhna chahte? Permanent unlock karein 👇",
                  style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                
                // Secondary Action: Buy Premium
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      OfferTrialScreen.show(context);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.amber.withValues(alpha: 0.6), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      foregroundColor: Colors.amber,
                      backgroundColor: Colors.amber.withValues(alpha: 0.05),
                    ),
                    child: const Text("GET UNLIMITED GOLD (BUY NOW)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRewardGrantedPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 30, spreadRadius: 10)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 50),
              ),
              const SizedBox(height: 24),
              const Text(
                "Reward Granted!",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 12),
              Text(
                "Congratulations! You have unlocked Premium features for the next ${AppConfigService().rewardDurationMinutes} minutes. Enjoy chatting without limits!",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper to decide if aggressive ads (Feed/Profile) should be shown.
  /// Note: These ads continue to show even during temporary trial access
  /// to maintain revenue flow. Only real paid Premium removes them.
  bool get shouldShowAggressiveAds {
    // Priority 1: Real Paid Premium status removes all ads.
    if (PremiumService().isPremium) return false;
    
    // Priority 2: Master Switch from Backend.
    if (!AppConfigService().isAdsEnabled) return false;
    
    // Priority 3: Only users in Ad-Driven segment see these ads.
    // Temporary access from rewarded ads does NOT hide these home/profile ads.
    return _currentMode == MonetizationMode.adDriven;
  }
}
