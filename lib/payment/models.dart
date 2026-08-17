library payment_models;

/// 会员套餐、订单与权益的数据模型。
/// 前端与后端 worker.js 的字段需对齐（详见 PAYMENT_SETUP.md）。

/// 会员套餐。价格仅为示意，正式以你在微信/支付宝商户平台配置为准。
enum Plan {
  monthly('monthly', '按月会员', 6.0),
  yearly('yearly', '按年会员', 60.0),
  lifetime('lifetime', '永久会员', 198.0);

  const Plan(this.id, this.label, this.priceCny);
  final String id;
  final String label;
  final double priceCny; // 人民币（¥）
}

/// 后端创建订单后返回给前端的拉起支付信息。
class Order {
  const Order({
    required this.orderId,
    required this.payUrl,
    required this.plan,
  });
  final String orderId;
  final String payUrl; // 微信/支付宝的 H5 或网站支付 URL
  final Plan plan;
}

/// 会员权益状态（后端为唯一真源）。
class Entitlement {
  const Entitlement({
    required this.isPremium,
    this.expireAt,
    this.source,
  });
  final bool isPremium;
  final DateTime? expireAt;
  final String? source; // 'redeem' | 'purchase'
}
