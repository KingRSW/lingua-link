library payment_models;

/// 会员套餐、订单与权益的数据模型。
/// 前端与后端 worker.js 的字段需对齐（详见 PAYMENT_SETUP.md）。

/// 会员套餐。价格仅为示意，正式以你在微信/支付宝商户平台配置为准。
enum Plan {
  monthly('monthly', '按月会员', 1.0),
  yearly('yearly', '按年会员', 10.0);

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
    this.codeUrl,
    this.mode,
    this.wxQr,
    this.aliQr,
    this.priceCny,
    this.label,
  });
  final String orderId;
  final String payUrl; // 微信/支付宝的 H5 或网站支付 URL
  final Plan plan;
  final String? codeUrl; // 微信 NATIVE 真实模式：二维码内容，由 App 内渲染后扫码
  final String? mode; // 收款模式：dev | personal | wechat | alipay
  final String? wxQr; // 个人收款码模式：微信收款码图片地址
  final String? aliQr; // 个人收款码模式：支付宝收款码图片地址
  final double? priceCny; // 个人收款码模式：金额
  final String? label; // 个人收款码模式：套餐名
}

/// 会员权益状态（后端为唯一真源）。
class Entitlement {
  const Entitlement({
    required this.isPremium,
    this.expireAt,
    this.source,
    this.token,
  });
  final bool isPremium;
  final DateTime? expireAt;
  final String? source; // 'redeem' | 'purchase'
  /// 后端签发的 membership token（HS256）。调用 PRO 权益接口（/ai-polish、/ocr）时带上。
  final String? token;
}
