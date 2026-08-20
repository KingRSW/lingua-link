import 'package:flutter/material.dart';

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

  /// 走支付流程：下单 → 拉起收银台 → 轮询权益。
  Future<void> _pay(Plan plan) async {
    setState(() {
      _busy = true;
      _payingPlan = plan;
      _msg = null;
    });
    try {
      final order = await _provider.createOrder(plan);
      await _provider.launchPay(order);

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
      case Plan.lifetime:
        return '一次买断 · 永久有效';
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
            child: Text('微信 / 支付宝安全支付 · 随时可取消',
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
