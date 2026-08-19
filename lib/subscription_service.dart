import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'payment/models.dart';

/// 会员权益服务：前端唯一的「高级功能」状态入口。
///
/// 设计：
/// - 权益（Entitlement）本地只做缓存，真正真源是后端 worker.js；
///   付费购买成功后由支付层把后端签发的 Entitlement 写入这里。
/// - 兑换码（redeemCode）仍是纯本地校验，适合开发者分发 / 灰度 / 补偿，不依赖后端。
/// - 纯前端校验可被技术用户绕过；若要「不可绕过」，付费权益以后端为准即可
///   （兑换码场景对独立小工具足够，详见 PAYMENT_SETUP.md）。
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const String _prefsKey = 'lingua_premium_v1';

  Entitlement _entitlement = const Entitlement(isPremium: false);
  Entitlement get entitlement => _entitlement;

  /// 是否高级会员（由 entitlement 派生）。
  bool get isPremium => _entitlement.isPremium;

  /// 是否拥有某 PRO 专属功能（当前所有 PRO 功能都要求 isPremium）。
  bool hasPro(ProFeature f) => isPremium;

  /// 全部 PRO 专属工具（用于付费墙展示 / UI 遍历）。
  static const List<ProFeature> proTools = ProFeature.values;

  /// 免费版 / 高级版 单次翻译字数上限
  int get freeLimit => 500;
  int get premiumLimit => 5000;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        _entitlement = const Entitlement(isPremium: false);
        return;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _entitlement = Entitlement(
        isPremium: map['isPremium'] as bool? ?? false,
        expireAt: map['expireAt'] == null
            ? null
            : DateTime.parse(map['expireAt'] as String),
        source: map['source'] as String?,
      );
    } catch (_) {
      _entitlement = const Entitlement(isPremium: false);
    }
  }

  Future<void> _persist(Entitlement e) async {
    _entitlement = e;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'isPremium': e.isPremium,
          'expireAt': e.expireAt?.toIso8601String(),
          'source': e.source,
        }),
      );
    } catch (_) {}
  }

  /// 兑换码解锁（本地校验，详情见 _checksum）。
  /// 返回是否成功；成功后写入本地 entitlement（source = 'redeem'）。
  bool redeemCode(String raw) {
    final code = raw.trim().toUpperCase();
    final parts = code.split('-');
    if (parts.length != 3) return false;
    if (parts[0] != 'LINGUA') return false;
    final middle = parts[1];
    final given = parts[2];
    if (middle.length != 6 || given.length != 6) return false;
    if (!RegExp(r'^[0-9A-Z]{12}$').hasMatch(middle + given)) return false;
    if (_checksum(middle) != given) return false;
    unawaited(
      _persist(const Entitlement(isPremium: true, source: 'redeem')),
    );
    return true;
  }

  /// 付费购买成功后由支付层调用，写入后端签发的权益（source = 'purchase'）。
  Future<void> activatePurchase(Entitlement e) => _persist(e);

  // --- 校验和（务必与 tools/gen_code.dart 保持一致）---
  // 关键：用 _mul32 拆 16-bit 半段做 32-bit 乘法，避免 dart2js 编译到 JS 时
  // 把 (h * p) 算成 IEEE-754 双精度（h≈2^32, p≈2^24 时乘积超 2^53 丢精度），
  // 导致 Web 端校验和与 Dart VM 端（Dart int=64-bit）算出来的不一致。
  static const String _salt = 'LinguaLink-2026-StaticSite';
  static int _mul32(int h, int p) {
    final lo = (h & 0xFFFF) * p; // < 2^40，53-bit 双精度内安全
    final hi = ((h >> 16) & 0xFFFF) * p;
    return (lo + ((hi & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  static String _checksum(String seed) {
    int h = 0x811c9dc5; // FNV offset basis
    final s = seed + _salt;
    for (int i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = _mul32(h, 16777619); // FNV-1a 32-bit（JS-safe）
    }
    h = (h ^ (h >> 13)) & 0xFFFFFFFF;
    h = _mul32(h, 0x5bd1e995); // murmur 混合（JS-safe）
    h = (h ^ (h >> 15)) & 0xFFFFFFFF;
    final hex = h.toRadixString(36).toUpperCase().padLeft(7, '0');
    return hex.substring(0, 6);
  }

  /// 生成解锁码（与 gen_code.dart 同算法），用于分发解锁高级功能。
  static String generateCode(String middle) {
    final m = middle.toUpperCase();
    return 'LINGUA-$m-${_checksum(m)}';
  }
}

/// PRO 专属功能/工具。
enum ProFeature {
  document, // 文档翻译
  export, // 导出 / 分享
  glossary, // 术语库
  voiceChat, // 实时语音对话
  ocr, // 拍照翻译
}

/// PRO 功能的展示元数据（标签 / 描述 / 图标）。
extension ProFeatureMeta on ProFeature {
  String get label {
    switch (this) {
      case ProFeature.document:
        return '文档翻译';
      case ProFeature.export:
        return '导出 / 分享';
      case ProFeature.glossary:
        return '术语库';
      case ProFeature.voiceChat:
        return '实时语音对话';
      case ProFeature.ocr:
        return '拍照翻译';
    }
  }

  String get desc {
    switch (this) {
      case ProFeature.document:
        return '上传 PDF/Word/TXT 整篇翻译';
      case ProFeature.export:
        return '结果导出 PDF/Word/Markdown 或一键分享';
      case ProFeature.glossary:
        return '自定义专业词表，术语保持一致';
      case ProFeature.voiceChat:
        return '实时双语语音互译';
      case ProFeature.ocr:
        return '拍照 / 选图 OCR 翻译';
    }
  }

  IconData get icon {
    switch (this) {
      case ProFeature.document:
        return Icons.description_outlined;
      case ProFeature.export:
        return Icons.share_outlined;
      case ProFeature.glossary:
        return Icons.menu_book_outlined;
      case ProFeature.voiceChat:
        return Icons.record_voice_over_outlined;
      case ProFeature.ocr:
        return Icons.camera_alt_outlined;
    }
  }
}
