import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

/// 支付后端地址（Cloudflare Workers 部署后得到）。
/// 通过编译参数注入，避免把后端地址写死在代码里：
///   flutter build web --dart-define=PAYMENT_BACKEND=https://lingua-pay.your-sub.workers.dev
const String kPaymentBackendBaseUrl = String.fromEnvironment(
  'PAYMENT_BACKEND',
  defaultValue: '',
);

/// DEV 模式：尚未配置真实微信/支付宝商户号时，用模拟下单直接把 UI 流程跑通，
/// 不会真实扣款，仅用于验证交互。配置好真实后端后请关闭：
///   flutter build web --dart-define=PAYMENT_DEV=false --dart-define=PAYMENT_BACKEND=https://...
const bool kPaymentDevMode = bool.fromEnvironment(
  'PAYMENT_DEV',
  defaultValue: true,
);

/// 支付提供方抽象。前端只依赖此接口，真实实现（微信/支付宝）走后端 worker.js。
abstract class PaymentProvider {
  /// 创建订单，返回用于拉起支付的 Order。
  Future<Order> createOrder(Plan plan);

  /// 拉起支付（H5 / 网站支付页）。
  Future<void> launchPay(Order order);

  /// 查询该订单对应的会员权益状态（后端为唯一真源）。
  Future<Entitlement> queryEntitlement(String orderId);
}

/// 微信 / 支付宝 支付实现：所有敏感签名都在后端 worker.js 完成，前端只负责
/// 下单 → 拉起收银台 → 轮询权益，不接触任何商户密钥。
class WechatAlipayProvider implements PaymentProvider {
  WechatAlipayProvider([this.backendUrl = kPaymentBackendBaseUrl]);

  final String backendUrl;

  bool get _dev => kPaymentDevMode || backendUrl.isEmpty;

  @override
  Future<Order> createOrder(Plan plan) async {
    if (_dev) {
      // DEV：返回模拟订单，便于先把 UI 跑通（不真实扣款）。
      final orderId = 'DEV-${DateTime.now().millisecondsSinceEpoch}';
      return Order(
        orderId: orderId,
        payUrl:
            'https://example.com/dev-pay?plan=${plan.id}&order=$orderId',
        plan: plan,
      );
    }

    final resp = await http.post(
      Uri.parse('$backendUrl/create-order'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'plan': plan.id}),
    );
    if (resp.statusCode != 200) {
      throw Exception('下单失败（${resp.statusCode}）');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Order(
      orderId: data['orderId'] as String,
      payUrl: data['payUrl'] as String,
      plan: plan,
    );
  }

  @override
  Future<void> launchPay(Order order) async {
    final uri = Uri.parse(order.payUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('无法打开支付页面：$uri');
    }
  }

  @override
  Future<Entitlement> queryEntitlement(String orderId) async {
    if (_dev) {
      // DEV：假定支付已成功，立即返回权益（仅用于联调）。
      return const Entitlement(isPremium: true, source: 'purchase');
    }

    final resp = await http.get(
      Uri.parse('$backendUrl/entitlement?orderId=$orderId'),
    );
    if (resp.statusCode != 200) {
      throw Exception('查询权益失败（${resp.statusCode}）');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Entitlement(
      isPremium: data['isPremium'] as bool? ?? false,
      expireAt: data['expireAt'] == null
          ? null
          : DateTime.parse(data['expireAt'] as String),
      source: data['source'] as String?,
    );
  }
}
