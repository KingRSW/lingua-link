import 'package:flutter/material.dart';
import 'subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _codeCtrl = TextEditingController();
  String? _msg;
  bool _busy = false;

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
      await Future.delayed(const Duration(seconds: 1), () => Navigator.of(context).pop());
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
          const Text('如何解锁',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            '输入解锁码即可解锁全部高级功能。',
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

class _Feature {
  final IconData icon;
  final String title;
  final String desc;
  const _Feature(this.icon, this.title, this.desc);
}
