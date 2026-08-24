import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'payment/models.dart';
import 'payment/payment_provider.dart';
import 'subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _codeCtrl = TextEditingController();
  final PaymentProvider _provider = WechatAlipayProvider();
  String? _msg;
  bool _busy = false;
  Plan? _payingPlan;
  Plan _selectedPlan = Plan.yearly; // 默认推荐年付

  static const Color _accent = Color(0xFF5D6CFF);
  static const Color _ink = Color(0xFF202536);
  static const Color _sub = Color(0xFF8A8F9C);
  static const Color _bg = Color(0xFFF7F7FA);

  static const List<_Feature> _features = [
    _Feature('长文本翻译', '单次可翻译 5000 字（免费版仅 500 字）'),
    _Feature('翻译历史', '自动保存最近 50 条翻译记录'),
    _Feature('云端同步', '多设备共享翻译记录'),
    _Feature('无广告', '纯净界面，没有任何广告'),
    _Feature('优先通道', '高峰期优先翻译队列'),
  ];

  static const List<_Feature> _proToolFeatures = [
    _Feature('文档翻译', '上传 PDF/Word/TXT 整篇翻译'),
    _Feature('导出 / 分享', '结果导出 PDF/Word/Markdown 或一键分享'),
    _Feature('术语库', '自定义专业词表，术语保持一致'),
    _Feature('实时语音对话', '实时双语语音互译'),
    _Feature('拍照翻译', '拍照 / 选图 OCR 翻译'),
  ];

  @override
  void initState() {
    super.initState();
    _resumePending();
  }

  /// 重进付费页时补查上次未完成的订单：卖家可能在别的界面已确认，
  /// 若已 paid 则自动开通，避免「确认成功却没开通」。
  Future<void> _resumePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oid = prefs.getString('lingua_pending_order');
      if (oid == null || oid.isEmpty) return;
      final e = await _provider.queryEntitlement(oid);
      if (e.isPremium) {
        await SubscriptionService.instance.activatePurchase(e);
        await prefs.remove('lingua_pending_order');
      }
    } catch (_) {
      // 忽略：下次进入再补查
    }
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    final ok = await SubscriptionService.instance.redeemCode(_codeCtrl.text);
    setState(() {
      _busy = false;
      _msg = ok ? '✅ 已解锁高级功能！' : '❌ 解锁码无效，请检查后重试';
    });
    if (ok) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 微信真实模式：在 App 内渲染支付二维码，用户扫码付款。
  Future<void> _showWxQrDialog(String codeUrl) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('微信扫码支付'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFE4E4EC)),
              ),
              child: QrImageView(
                data: codeUrl,
                version: QrVersions.auto,
                size: 220,
                gapless: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text('用微信「扫一扫」完成支付，支付成功后将自动开通。',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8F9C)),
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我已支付 / 关闭'),
          ),
        ],
      ),
    );
  }

  /// 个人收款码模式（免营业执照）：展示微信/支付宝收款码，用户扫码付款后凭解锁码激活。
  Future<void> _showPersonalQrDialog(Order order) async {
    debugPrint('[paywall] _showPersonalQrDialog: wxQr=${order.wxQr} aliQr=${order.aliQr} label=${order.label} priceCny=${order.priceCny}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('开通${order.label ?? ''} · ¥${order.priceCny?.toStringAsFixed(0) ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order.wxQr != null && order.wxQr!.isNotEmpty)
                _QrTile(label: '微信支付', url: order.wxQr!)
              else
                const Text('（未配置微信收款码）', style: TextStyle(fontSize: 13, color: Color(0xFF8A8F9C))),
              const SizedBox(height: 14),
              if (order.aliQr != null && order.aliQr!.isNotEmpty)
                _QrTile(label: '支付宝', url: order.aliQr!)
              else
                const Text('（未配置支付宝收款码）', style: TextStyle(fontSize: 13, color: Color(0xFF8A8F9C))),
              const SizedBox(height: 14),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText('订单号：${order.orderId}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5D6CFF), fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              const Text('付款后把订单号发给卖家，卖家确认后自动开通',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A8F9C)), textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Widget _QrTile({ required String label, required String url }) {
    // 相对路径按当前页面 origin 解析（图床放 web/pay_qr/ 时无需填绝对 URL）；绝对 URL/data URL 直接传。
    String src;
    try {
      if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:')) {
        src = url;
      } else {
        final base = Uri.base;
        src = (base != null && base.toString().isNotEmpty)
            ? base.resolve(url).toString()
            : url;
      }
    } catch (_) {
      src = url;
    }
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF202536))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFFE4E4EC)),
          ),
          child: src.isEmpty
              ? const Text('图片地址为空', style: TextStyle(fontSize: 12, color: Color(0xFF8A8F9C)))
              : Image(
                  image: NetworkImage(src),
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext ctx, Object err, StackTrace? stack) =>
                    const Text('图片加载失败', style: TextStyle(fontSize: 12, color: Color(0xFF8A8F9C))),
                ),
        ),
      ],
    );
  }

  /// 走支付流程：下单 → 拉起收银台 → 轮询权益。
  Future<void> _pay(Plan plan) async {
    setState(() {
      _busy = true;
      _payingPlan = plan;
      _msg = null;
    });
    try {
      debugPrint('[paywall] _pay: plan=${plan.id}');
      Order order;
      try {
        order = await _provider.createOrder(plan);
      } catch (e) {
        throw Exception('【下单阶段】$e');
      }
      debugPrint('[paywall] order: mode=${order.mode} label=${order.label} priceCny=${order.priceCny} wxQr=${order.wxQr} aliQr=${order.aliQr} orderId.len=${order.orderId.length} payUrl.len=${order.payUrl.length}');
      if (order.mode == 'personal') {
        // 记下本机待确认订单，便于离开本页后（卖家在别处确认）重进时补查开通。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lingua_pending_order', order.orderId);
        } catch (_) {}
        // 个人收款码模式（免营业执照）：展示收款码，收款方确认收款后会员自动开通（用户免输码）。
        try {
          if (mounted) await _showPersonalQrDialog(order);
        } catch (e) {
          throw Exception('【弹窗阶段】$e');
        }
        // 轮询：收款方在微信/支付宝看到到账并确认后，订单标记 paid，此处自动开通。
        Entitlement e = const Entitlement(isPremium: false);
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          e = await _provider.queryEntitlement(order.orderId);
          if (e.isPremium) break;
        }
        if (e.isPremium) {
          await SubscriptionService.instance.activatePurchase(e);
          try {
            (await SharedPreferences.getInstance()).remove('lingua_pending_order');
          } catch (_) {}
          setState(() => _msg = '✅ 会员已开通！');
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) Navigator.of(context).pop();
        } else {
          setState(() => _msg = '💡 已付款？把订单号发给卖家，卖家确认后自动开通');
        }
        return;
      }
      if (order.codeUrl != null && order.codeUrl!.isNotEmpty) {
        // 微信真实模式：App 内渲染二维码，用户用微信「扫一扫」付款。
        if (mounted) await _showWxQrDialog(order.codeUrl!);
      } else {
        await _provider.launchPay(order);
      }

      // 轮询后端权益状态（用户支付完成后后端才会返回 isPremium=true）。
      Entitlement e = const Entitlement(isPremium: false);
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        e = await _provider.queryEntitlement(order.orderId);
        if (e.isPremium) break;
      }

      if (e.isPremium) {
        await SubscriptionService.instance.activatePurchase(e);
        setState(() => _msg = '✅ 会员已开通！');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _msg = '⏳ 暂未检测到支付成功，可在支付完成后重新进入本页刷新');
      }
    } catch (err) {
      setState(() => _msg = '⚠️ 支付出错：$err');
    } finally {
      setState(() {
        _busy = false;
        _payingPlan = null;
      });
    }
  }

  /// 套餐副标题（每期价格 / 折算到每月）。
  String _planHint(Plan plan) {
    switch (plan) {
      case Plan.monthly:
        return '按月计费';
      case Plan.yearly:
        return '约 ¥${(plan.priceCny / 12).toStringAsFixed(1)} / 月';
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = SubscriptionService.instance.isPremium;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('升级 PRO',
            style: TextStyle(
                color: _ink, fontWeight: FontWeight.w600, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (premium)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('✓ 你已解锁全部高级功能',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
            ),
          const Text('解锁全部高级功能',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 6),
          const Text('更长文本 · 历史记录 · 云端同步 · 无广告',
              style: TextStyle(fontSize: 14, color: _sub)),
          const SizedBox(height: 22),

          // 权益列表（极简勾选式）
          ..._features.map((f) => _FeatureRow(f: f)),
          const SizedBox(height: 22),
          const Text('PRO 专属工具',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 12),
          ..._proToolFeatures.map((f) => _FeatureRow(f: f)),
          const SizedBox(height: 28),

          const Text('选择套餐',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 12),
          ...Plan.values.map(
            (plan) => _PlanCard(
              plan: plan,
              selected: _selectedPlan == plan,
              recommended: plan == Plan.yearly,
              hint: _planHint(plan),
              onTap: _busy ? null : () => setState(() => _selectedPlan = plan),
            ),
          ),
          const SizedBox(height: 20),

          // 单一 CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _pay(_selectedPlan),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy && _payingPlan == _selectedPlan
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text('立即订阅 · ¥${_selectedPlan.priceCny.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text('微信 / 支付宝收款码支付 · 付款后凭解锁码激活',
                style: TextStyle(fontSize: 12, color: _sub)),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 14),
            Text(_msg!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
          ],

          const SizedBox(height: 26),
          const Divider(height: 1, color: Color(0xFFECECF1)),
          const SizedBox(height: 20),

          // 解锁码（极简）
          const Text('有解锁码？',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 6),
          const Text('如果你有开发者分发的解锁码，可在此直接解锁。',
              style: TextStyle(fontSize: 13, color: _sub)),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              hintText: 'LINGUA-XXXXXX-XXXXXX',
              hintStyle: const TextStyle(color: Color(0xFFB5B9C4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E4EC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E4EC)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accent.withValues(alpha: 0.6)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _busy ? null : _redeem,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: Color(0xFFE4E4EC)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('验证并解锁',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.f});
  final _Feature f;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF5D6CFF).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.check_rounded,
                size: 15, color: Color(0xFF5D6CFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF202536))),
                const SizedBox(height: 1),
                Text(f.desc,
                    style:
                        const TextStyle(fontSize: 12.5, color: Color(0xFF8A8F9C))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.recommended,
    required this.hint,
    this.onTap,
  });
  final Plan plan;
  final bool selected;
  final bool recommended;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFF5D6CFF).withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFF5D6CFF)
                    : const Color(0xFFECECF1),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(plan.label,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF202536))),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5D6CFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('推荐',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(hint,
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF8A8F9C))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('¥${plan.priceCny.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF202536))),
                    const SizedBox(height: 4),
                    _SelectDot(selected: selected),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xFF5D6CFF) : Colors.transparent,
        border: Border.all(
          color: selected
              ? const Color(0xFF5D6CFF)
              : const Color(0xFFC8CCD6),
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _Feature {
  final String title;
  final String desc;
  const _Feature(this.title, this.desc);
}
