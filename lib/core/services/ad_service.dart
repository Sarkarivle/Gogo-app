import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'package:gogo/core/services/app_config_service.dart';
import 'package:gogo/core/services/monetization_orchestrator.dart';
import 'dart:math';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;
  int _interstitialRetryAttempt = 0;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  int _rewardedRetryAttempt = 0;

  DateTime? _lastInterstitialTime;
  final DateTime _appStartTime = DateTime.now();

  bool get shouldShowAds {
    // INTELLIGENT OVERRIDE:
    // Only show aggressive ads (Feeds, Interstitials, Native) to users in Ad-Driven Mode.
    // Temporary 1-hour access from rewards does NOT hide these ads; only paid Premium does.
    return MonetizationOrchestrator().shouldShowAggressiveAds;
  }

  String get _activeProvider => AppConfigService().adsConfig?['activeProvider'] ?? 'google';
  Map<String, dynamic> get _providerConfig => AppConfigService().adsConfig?[_activeProvider] ?? {};

  String get bannerAdUnitId => _providerConfig['bannerId'] ?? '';
  String get interstitialAdUnitId => _providerConfig['interstitialId'] ?? '';
  String get rewardedAdUnitId => _providerConfig['rewardedId'] ?? '';
  String get nativeAdUnitId => _providerConfig['nativeId'] ?? '';

  Future<void> init() async {
    await MobileAds.instance.initialize();
    
    // Disable Native Ad Validator and configure request
    RequestConfiguration configuration = RequestConfiguration(
      testDeviceIds: [], // Add your test device IDs here if needed
    );
    await MobileAds.instance.updateRequestConfiguration(configuration);

    reloadAds();
  }

  void reloadAds() {
    loadInterstitialAd();
    loadRewardedAd();
  }

  // --- Interstitial Ads ---

  void loadInterstitialAd() {
    if (!shouldShowAds || interstitialAdUnitId.isEmpty || _isInterstitialAdLoading) return;

    _isInterstitialAdLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          _interstitialRetryAttempt = 0;
          debugPrint('InterstitialAd loaded.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load: $error');
          _isInterstitialAdLoading = false;
          _interstitialRetryAttempt++;
          if (_interstitialRetryAttempt < 5) {
            Future.delayed(Duration(seconds: pow(2, _interstitialRetryAttempt).toInt()), () {
              loadInterstitialAd();
            });
          }
        },
      ),
    );
  }

  void showInterstitialAd({VoidCallback? onAdClosed}) {
    if (!shouldShowAds) {
      onAdClosed?.call();
      return;
    }

    // POLICY PROTECTION: Avoid showing ads immediately on app launch
    // AdSense policy discourages interstitials on startup screens.
    // We add a 10-second grace period from app start.
    if (DateTime.now().difference(_appStartTime).inSeconds < 10) {
      debugPrint('AdService: Skipping interstitial due to App Start Grace Period.');
      onAdClosed?.call();
      return;
    }

    // Frequency capping from Admin Panel
    final frequency = AppConfigService().adsConfig?['frequencyMinutes'] ?? 5;
    if (_lastInterstitialTime != null) {
      if (DateTime.now().difference(_lastInterstitialTime!).inMinutes < frequency) {
        debugPrint('AdService: Capping interstitial. Last shown less than $frequency min ago.');
        onAdClosed?.call();
        return;
      }
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

  // --- Rewarded Ads ---

  void loadRewardedAd() {
    if (!shouldShowAds || rewardedAdUnitId.isEmpty || _isRewardedAdLoading) return;

    _isRewardedAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
          _rewardedRetryAttempt = 0;
          debugPrint('RewardedAd loaded.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _isRewardedAdLoading = false;
          _rewardedRetryAttempt++;
          if (_rewardedRetryAttempt < 5) {
            Future.delayed(Duration(seconds: pow(2, _rewardedRetryAttempt).toInt()), () {
              loadRewardedAd();
            });
          }
        },
      ),
    );
  }

  bool isRewardedAdLoaded() => _rewardedAd != null;

  void showRewardedAd({required Function(RewardItem) onRewardEarned, VoidCallback? onAdClosed}) {
    if (!shouldShowAds) {
      onAdClosed?.call();
      return;
    }

    if (_rewardedAd == null) {
      debugPrint('RewardedAd is null. Trying to load...');
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

    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
      onRewardEarned(reward);
    });
  }

  // --- Helper Widgets ---

  Widget getBannerAdWidget() {
    if (!shouldShowAds || bannerAdUnitId.isEmpty) return const SizedBox.shrink();

    return BannerAdWidget(adUnitId: bannerAdUnitId);
  }

  Widget getNativeAdWidget() {
    if (!shouldShowAds || nativeAdUnitId.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: Text(
            "SPONSORED",
            style: TextStyle(fontSize: 7, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            clipBehavior: Clip.antiAlias,
            child: NativeAdWidget(adUnitId: nativeAdUnitId),
          ),
        ),
      ],
    );
  }

  Widget getMediumRectangleAdWidget() {
    if (!shouldShowAds || bannerAdUnitId.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, size: 10, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 6),
              const Text(
                "SPONSORED ADVERTISEMENT",
                style: TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            alignment: Alignment.center,
            width: 300,
            height: 250,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: BannerAdWidget(adUnitId: bannerAdUnitId, size: AdSize.mediumRectangle),
          ),
        ],
      ),
    );
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
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('BannerAd failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
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
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: 'listTile', // You need to implement this in Android/iOS native side or use standard
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('NativeAd failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();
    return AdWidget(ad: _nativeAd!);
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }
}
