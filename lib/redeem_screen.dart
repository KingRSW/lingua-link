import 'package:flutter/material.dart';
import 'subscription_service.dart';

/// 独立的「兑换码」页面：用户可随时从主界面顶部进入，输入解锁码解锁高级功能。
/// 校验逻辑全部复用 SubscriptionService.redeemCode（与发卡脚本 tools/gen_code.dart 同算法）。
class RedeemScreen extends StatefulWidget {
  const RedeemScreen({super.key});

  @override
  State<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends State<RedeemScreen> {
  final _codeCtrl = TextEditingController();
  String? _msg;
  bool _ok = false;
  bool _busy = false;

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _msg = null;
      _ok = false;
    });
    // 轻微延时，让 loading 态可见（也避免误以为没反应）
    await Future.delayed(const Duration(milliseconds: 200));
    final ok = SubscriptionService.instance.redeemCode(_codeCtrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = ok;
      _msg = ok ? '✅ 兑换成功，已解锁高级功能！' : '❌ 兑换码无效，请检查格式后重试';
    });
    if (ok) {
      // 兑换成功后自动返回主页（返回结果 true，主页据此刷新状态）
      await Future.delayed(const Duration(seconds: 1, milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = SubscriptionService.instance.isPremium;
    const accent = Color(0xFF5D6CFF);
    return Scaffold(
      appBar: AppBar(title: const Text('兑换码')),
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
          const SizedBox(height: 12),
          const Text('输入解锁码，立即解锁高级功能',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('解锁码格式：LINGUA-XXXXXX-XXXXXX',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '解锁码',
              hintText: 'LINGUA-XXXXXX-XXXXXX',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : _redeem,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('兑换'),
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _msg!,
                style: TextStyle(
                  fontSize: 14,
                  color: _ok
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text('如何获得解锁码',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '成为开发者的 GitHub 赞助者（按月订阅，开发者免手续费）后，'
            '开发者会发送专属解锁码给你，在此输入即可解锁。',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
