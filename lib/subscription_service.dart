import 'package:shared_preferences/shared_preferences.dart';

/// 高级功能订阅服务（纯前端实现，无需后端）
///
/// 设计：
/// - 付费通道用 GitHub Sponsors：开发者免费开通、GitHub 不抽成、按月订阅。
/// - 解锁方式：赞助者由开发者发放「解锁码」，在网页里输入即解锁。
///   校验在本地完成（格式 + 校验和），因此可在纯静态的 GitHub Pages 上运行。
/// - 说明：纯前端校验可被技术用户绕过，对独立小工具足够；
///   若要做到「不可绕过」，可加一个 serverless 校验函数（如 Cloudflare Workers，免费额度足够）。
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const String _prefsKey = 'lingua_premium_v1';

  /// 你的 GitHub 用户名（赞助页地址 https://github.com/sponsors/<这里>）
  /// ⚠️ 上线前改成你自己的用户名。
  static const String sponsorHandle = 'KingRSW';

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  /// 免费版 / 高级版 单次翻译字数上限
  int get freeLimit => 500;
  int get premiumLimit => 5000;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      _isPremium = false;
    }
  }

  Future<void> setPremium(bool value) async {
    _isPremium = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  /// 校验解锁码：格式 LINGUA-XXXXXX-XXXXXX，末段为前段的校验和。
  bool redeemCode(String raw) {
    final code = raw.trim().toUpperCase();
    final parts = code.split('-');
    if (parts.length != 3) return false;
    if (parts[0] != 'LINGUA') return false;
    final middle = parts[1];
    final given = parts[2];
    if (middle.length != 6 || given.length != 6) return false;
    if (!RegExp(r'^[0-9A-Z]{6}$').hasMatch(middle + given)) return false;
    if (_checksum(middle) != given) return false;
    setPremium(true);
    return true;
  }

  /// 仅供本地测试：临时切换解锁状态。生产环境请把这个方法和 Paywall 里的「测试」按钮删掉。
  Future<void> toggleDevUnlock() async => setPremium(!_isPremium);

  // --- 校验和（务必与 tools/gen_code.dart 保持一致）---
  static const String _salt = 'LinguaLink-2026-StaticSite';
  static String _checksum(String seed) {
    int h = 0x811c9dc5; // FNV offset basis
    final s = seed + _salt;
    for (int i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 16777619) & 0xFFFFFFFF; // FNV-1a 32-bit
    }
    h = (h ^ (h >> 13)) & 0xFFFFFFFF;
    h = (h * 0x5bd1e995) & 0xFFFFFFFF;
    h = (h ^ (h >> 15)) & 0xFFFFFFFF;
    final hex = h.toRadixString(36).toUpperCase().padLeft(7, '0');
    return hex.substring(0, 6);
  }

  /// 生成解锁码（与 gen_code.dart 同算法），用于给赞助者发卡。
  static String generateCode(String middle) {
    final m = middle.toUpperCase();
    return 'LINGUA-$m-${_checksum(m)}';
  }
}
