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

  static const List<_Feature> _features = [
    _Feature(Icons.text_fields_rounded, '长文本翻译', '单次可翻译 5000 字（免费版仅 500 字）'),
    _Feature(Icons.history_rounded, '翻译历史', '自动保存最近 50 条翻译记录'),
    _Feature(Icons.cloud_done_rounded, '云端同步', '多设备共享翻译记录'),
    _Feature(Icons.block_rounded, '无广告', '纯净界面，没有任何广告'),
    _Feature(Icons.speed_rounded, '优先通道', '高峰期优先翻译队列'),
  ];

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    final ok = SubscriptionService.instance.redeemCode(_codeCtrl.text);
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

  @override
  Widget build(BuildContext context) {
    final premium = SubscriptionService.instance.isPremium;
    return Scaffold(
      appBar: AppBar(title: const Text('高级功能')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (premium)
            const Center(
              child: Chip(
                label: Text('当前状态：已解锁 PRO'),
                backgroundColor: Color(0xFFE6F4EA),
              ),
            ),
          const SizedBox(height: 8),
          const Text('高级功能包含：',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ..._features.map(
            (f) => ListTile(
              leading: Icon(f.icon, color: const Color(0xFF5D6CFF)),
              title: Text(f.title),
              subtitle: Text(f.desc),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text('选择会员套餐',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ...Plan.values.map((plan) => _PlanCard(
                plan: plan,
                busy: _busy && _payingPlan == plan,
                onTap: _busy ? null : () => _pay(plan),
              )),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          const Text('使用解锁码',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            '如果你有开发者分发的解锁码，可在此输入直接解锁。',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              labelText: '输入解锁码',
              hintText: 'LINGUA-XXXXXX-XXXXXX',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _redeem,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('验证并解锁'),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_msg!, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.busy, this.onTap});
  final Plan plan;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(plan.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('¥${plan.priceCny.toStringAsFixed(0)}'),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5D6CFF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('微信/支付宝'),
              ),
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String desc;
  const _Feature(this.icon, this.title, this.desc);
}
