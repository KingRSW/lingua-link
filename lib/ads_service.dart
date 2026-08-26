import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pangle_ads/flutter_pangle_ads.dart';

/// 穿山甲（Pangle）广告接入层。
///
/// ⚠️ 注意：以下广告位均为穿山甲【官方测试位】，只能联调显示，不产生结算收益。
/// 真要收钱时，需在穿山甲后台（https://www.pangle.cn）用自己的 AppID + 广告位替换，
/// 且 app 必须上架 App Store 并通过穿山甲审核。
class AdService {
  // ---- 测试广告位（请勿直接用于生产结算）----
  static const String appId = '5324024';
  static const String bannerId = '949641731'; // Banner
  static const String interstitialId = '949641653'; // 新插屏 / 全屏视频
  static const String rewardId = '949641706'; // 激励视频

  /// 看完激励视频后获得的「一次免费体验」通行（内存态，App 退出即失效）。
  /// PRO 工具门禁在读到 true 时放行一次并立即消费掉。
  static bool sessionRewardUnlocked = false;

  static bool _initialized = false;
  static Completer<bool>? _rewardCompleter;

  /// 在 runApp 之前调用一次。初始化失败只记录日志，不阻塞启动。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (Platform.isIOS) {
        // iOS 14+ 需要 ATT 授权才能做个性化广告（单价更高）。拒绝或不支持都不影响测试广告展示。
        try {
          await FlutterPangleAds.requestIDFA;
        } catch (_) {
          // ignore
        }
      }
      final ok = await FlutterPangleAds.initAd(
        appId,
        directDownloadNetworkType: [
          NetworkType.kNetworkStateMobile,
          NetworkType.kNetworkStateWifi,
        ],
      );
      debugPrint('[ads] 初始化${ok ? '成功' : '失败'}');
      // 打开个性化推荐，提升 eCPM
      await FlutterPangleAds.setUserExtData(personalAdsType: '1');
      _registerListener();
    } catch (e) {
      debugPrint('[ads] 初始化异常：$e');
    }
  }

  static void _registerListener() {
    FlutterPangleAds.onEventListener((event) {
      debugPrint('[ads] adId=${event.adId} action=${event.action}');
      if (event is AdErrorEvent) {
        debugPrint('[ads] 错误 errCode=${event.errCode} errMsg=${event.errMsg}');
      } else if (event is AdRewardEvent) {
        // 用户看完视频，发放奖励
        final c = _rewardCompleter;
        _rewardCompleter = null;
        c?.complete(event.rewardVerify);
      }
    });
  }

  /// 新插屏 / 全屏视频广告（免费用户打开 PRO 工具页时展示）。
  static Future<bool> showInterstitial() async {
    try {
      return await FlutterPangleAds.showFullScreenVideoAd(interstitialId);
    } catch (e) {
      debugPrint('[ads] 插屏异常：$e');
      return false;
    }
  }

  /// 激励视频广告。返回 true 表示用户看完并通过服务端验证（可发放一次免费体验）。
  static Future<bool> showRewarded() async {
    _rewardCompleter = Completer<bool>();
    try {
      await FlutterPangleAds.showRewardVideoAd(rewardId);
    } catch (e) {
      _rewardCompleter = null;
      debugPrint('[ads] 激励视频异常：$e');
      return false;
    }
    try {
      final verified = await _rewardCompleter!.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          _rewardCompleter = null;
          return false;
        },
      );
      return verified;
    } catch (_) {
      _rewardCompleter = null;
      return false;
    }
  }
}
