import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/core/services/monetization_orchestrator.dart';
import 'dart:math';
import 'package:flutter/services.dart';

/// Production-Grade Ad Service with Hardcoded Fallbacks & Backend Sync
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // --- HARDCODED PRODUCTION FALLBACKS (From your screenshot) ---
  static const String _fallbackBannerId = "ca-app-pub-4668525700908893/7915589973";
  static const String _fallbackInterstitialId = "ca-app-pub-4668525700908893/7340874905";
  static const String _fallbackNativeId = "ca-app-pub-4668525700908893/4906283252";
  static const String _fallbackRewardedId = "ca-app-pub-4668525700908893/5160052170";

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;
  int _interstitialRetryAttempt = 0;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  int _rewardedRetryAttempt = 0;

  DateTime? _lastInterstitialTime;
  bool _isInitialized = false;

  bool get isAdsEnabled => AppConfigService().isAdsEnabled;
  
  bool get isBannerEnabled => _providerConfig['isBannerEnabled'] ?? true;
  bool get isNativeEnabled => _providerConfig['isNativeEnabled'] ?? true;
  bool get isInterstitialEnabled => _providerConfig['isInterstitialEnabled'] ?? true;
  bool get isRewardedEnabled => _providerConfig['isRewardedEnabled'] ?? true;

  bool get shouldShowAds {
    // Priority 1: Backend switch
    if (!isAdsEnabled) return false;
    // Priority 2: User segment (Payer vs Ad-Driven)
    return MonetizationOrchestrator().shouldShowAggressiveAds;
  }

  String get _activeProvider => AppConfigService().adsConfig?['activeProvider'] ?? 'google';
  Map<String, dynamic> get _providerConfig => AppConfigService().adsConfig?[_activeProvider] ?? {};

  // Logic: Backend ID > Cached ID > Hardcoded Fallback
  String get bannerAdUnitId => _providerConfig['bannerId']?.toString().isNotEmpty == true ? _providerConfig['bannerId'] : _fallbackBannerId;
  String get interstitialAdUnitId => _providerConfig['interstitialId']?.toString().isNotEmpty == true ? _providerConfig['interstitialId'] : _fallbackInterstitialId;
  String get rewardedAdUnitId => _providerConfig['rewardedId']?.toString().isNotEmpty == true ? _providerConfig['rewardedId'] : _fallbackRewardedId;
  String get nativeAdUnitId => _providerConfig['nativeId']?.toString().isNotEmpty == true ? _providerConfig['nativeId'] : _fallbackNativeId;

  Future<void> init() async {
    if (_isInitialized) {
      reloadAds();
      return;
    }

    try {
      debugPrint('AdService: Initializing Ads with Fallback Support...');
      await MobileAds.instance.initialize();
      _isInitialized = true;
      
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: [], // Empty for production. AdMob handles test devices via Dashboard.
        ),
      );

      reloadAds();
    } catch (e) {
      debugPrint('AdService: Init Error: $e');
    }
  }

  void reloadAds() {
    if (!shouldShowAds) return;
    if (isInterstitialEnabled) loadInterstitialAd();
    if (isRewardedEnabled) loadRewardedAd();
  }

  void loadInterstitialAd() {
    if (!shouldShowAds || !isInterstitialEnabled || _isInterstitialAdLoading) return;
    _isInterstitialAdLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          _interstitialRetryAttempt = 0;
          debugPrint('AdService: ✅ Interstitial loaded ($interstitialAdUnitId)');
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoading = false;
          _interstitialRetryAttempt++;
          if (_interstitialRetryAttempt < 5) {
            Future.delayed(Duration(seconds: pow(2, _interstitialRetryAttempt).toInt()), () => loadInterstitialAd());
          }
        },
      ),
    );
  }

  void showInterstitialAd({VoidCallback? onAdClosed}) {
    if (!shouldShowAds || !isInterstitialEnabled) {
      onAdClosed?.call();
      return;
    }

    final frequency = AppConfigService().adsConfig?['frequencyMinutes'] ?? 5;
    if (_lastInterstitialTime != null && DateTime.now().difference(_lastInterstitialTime!).inMinutes < frequency) {
      onAdClosed?.call();
      return;
    }

    if (_interstitialAd == null) {
      onAdClosed?.call();
      loadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _lastInterstitialTime = DateTime.now();
        ad.dispose();
        _interstitialAd = null;
        loadInterstitialAd();
        onAdClosed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitialAd();
        onAdClosed?.call();
      },
    );
    _interstitialAd!.show();
  }

  void loadRewardedAd() {
    if (!shouldShowAds || !isRewardedEnabled || _isRewardedAdLoading) return;
    _isRewardedAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
          _rewardedRetryAttempt = 0;
          debugPrint('AdService: ✅ Rewarded loaded ($rewardedAdUnitId)');
        },
        onAdFailedToLoad: (error) {
          _isRewardedAdLoading = false;
          _rewardedRetryAttempt++;
          if (_rewardedRetryAttempt < 5) {
            Future.delayed(Duration(seconds: pow(2, _rewardedRetryAttempt).toInt()), () => loadRewardedAd());
          }
        },
      ),
    );
  }

  bool isRewardedAdLoaded() => _rewardedAd != null;

  void showRewardedAd({required Function(RewardItem) onRewardEarned, VoidCallback? onAdClosed}) {
    if (!shouldShowAds || !isRewardedEnabled) {
      onAdClosed?.call();
      return;
    }
    if (_rewardedAd == null) {
      loadRewardedAd();
      onAdClosed?.call();
      return;
    }
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onAdClosed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onAdClosed?.call();
      },
    );
    _rewardedAd!.show(onUserEarnedReward: (ad, reward) => onRewardEarned(reward));
  }

  Widget getBannerAdWidget() => (!shouldShowAds || !isBannerEnabled) ? const SizedBox.shrink() : BannerAdWidget(adUnitId: bannerAdUnitId);

  Widget getNativeAdWidget() {
    if (!shouldShowAds || !isNativeEnabled) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("SPONSORED", style: TextStyle(fontSize: 7, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Flexible(
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
            clipBehavior: Clip.antiAlias,
            child: NativeAdWidget(adUnitId: nativeAdUnitId),
          ),
        ),
      ],
    );
  }

  Widget getMediumRectangleAdWidget() {
    if (!shouldShowAds || !isBannerEnabled) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("SPONSORED ADVERTISEMENT", style: TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          SizedBox(width: 300, height: 250, child: BannerAdWidget(adUnitId: bannerAdUnitId, size: AdSize.mediumRectangle)),
        ],
      ),
    );
  }

  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}

class BannerAdWidget extends StatefulWidget {
  final String adUnitId;
  final AdSize size;
  const BannerAdWidget({super.key, required this.adUnitId, this.size = AdSize.banner});
  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  @override
  void initState() { super.initState(); _loadAd(); }
  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) { if (mounted) setState(() => _isLoaded = true); },
        onAdFailedToLoad: (ad, error) { ad.dispose(); },
      ),
    )..load();
  }
  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(alignment: Alignment.center, width: _bannerAd!.size.width.toDouble(), height: _bannerAd!.size.height.toDouble(), child: AdWidget(ad: _bannerAd!));
  }
  @override
  void dispose() { _bannerAd?.dispose(); super.dispose(); }
}

class NativeAdWidget extends StatefulWidget {
  final String adUnitId;
  const NativeAdWidget({super.key, required this.adUnitId});
  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  @override
  void initState() { super.initState(); _loadAd(); }
  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: 'listTile',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) { if (mounted) setState(() => _isLoaded = true); },
        onAdFailedToLoad: (ad, error) { ad.dispose(); },
      ),
    )..load();
  }
  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();
    return AdWidget(ad: _nativeAd!);
  }
  @override
  void dispose() { _nativeAd?.dispose(); super.dispose(); }
}
