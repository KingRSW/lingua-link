import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'payment/models.dart';
import 'payment/payment_provider.dart';

/// 会员权益服务：前端唯一的「高级功能」状态入口。
///
/// 设计：
/// - 权益（Entitlement）本地只做缓存，真正真源是后端 worker.js。
/// - 兑换码（redeemCode）现在走后端 /redeem：服务端用 REDEEM_SECRET 校验签名，
///   成功则签发 membership token（HS256）并本地缓存。客户端不再自算校验和（旧算法可被逆向伪造）。
/// - 调用 PRO 权益接口（/ai-polish、/ocr）时，由 apiAuthHeaders 带上该 token，
///   后端校验签名+有效期+限频，未带有效 token 直接 401（防白嫖）。
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
        token: map['token'] as String?,
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
          'token': e.token,
        }),
      );
    } catch (_) {}
  }

  /// 后端签发的 membership token（HS256）；调用 /ai-polish、/ocr 时由 apiAuthHeaders 带上。
  String? get membershipToken => _entitlement.token;

  /// 调用 PRO 权益接口时的请求头（含 Supabase apikey + membership token）。
  Map<String, String> get apiAuthHeaders => backendHeaders(
        _entitlement.token != null
            ? {'authorization': 'Bearer ${_entitlement.token}'}
            : null,
      );

  /// 兑换码解锁：请求后端 /redeem，由服务端校验签名并签发 membership token。
  /// 返回是否成功；成功后写入本地 entitlement（带 token，source = 'redeem'）。
  /// 注意：未配置后端（kPaymentBackendBaseUrl 为空）时无法兑换，直接返回 false。
  Future<bool> redeemCode(String raw) async {
    final backend = kPaymentBackendBaseUrl;
    if (backend.isEmpty) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$backend/redeem'),
            headers: backendHeaders(),
            body: jsonEncode({'code': raw.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token == null) return false;
      await _persist(Entitlement(
        isPremium: true,
        source: 'redeem',
        token: token,
        expireAt: data['expireAt'] == null
            ? null
            : DateTime.parse(data['expireAt'] as String),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 付费购买成功后由支付层调用，写入后端签发的权益（source = 'purchase'）。
  Future<void> activatePurchase(Entitlement e) => _persist(e);

  /// 会员凭证失效（如后端返回 401）：清掉本地权益，回到未解锁状态。
  Future<void> clearMembership() =>
      _persist(const Entitlement(isPremium: false));
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
        return '上传 TXT/MD/CSV/DOCX 整篇翻译';
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
