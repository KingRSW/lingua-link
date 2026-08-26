import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'payment/models.dart';
import 'payment/payment_provider.dart';
import 'subscription_service.dart';

/// 卖家确认面板（个人收款码模式）。
/// - 首次使用输入一次 CONFIRM_SECRET，仅存本机（shared_preferences），之后不再手填。
/// - 打开即拉取「待确认订单」列表（后端 /seller-pending，需密钥）。
/// - 点「确认」→ 调 /confirm-paid（按 orderId）标 paid → 买家 App 轮询到后自动开通会员。
/// 全程不依赖快捷指令、不暴露后端 URL 给用户、密钥不烤进二进制。
class SellerConfirmScreen extends StatefulWidget {
  const SellerConfirmScreen({super.key});

  @override
  State<SellerConfirmScreen> createState() => _SellerConfirmScreenState();
}

class _SellerConfirmScreenState extends State<SellerConfirmScreen> {
  final _secretCtrl = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _secretSaved = false;
  List<Map<String, dynamic>> _orders = [];
  bool _loadingOrders = false;

  static const String _kSecret = 'lingua_confirm_secret';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kSecret);
    if (s != null && s.isNotEmpty) {
      setState(() => _secretSaved = true);
      await _refreshOrders();
    }
  }

  Future<String> _secret() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSecret) ?? '';
  }

  Future<void> _saveSecret() async {
    final s = _secretCtrl.text.trim();
    if (s.isEmpty) {
      setState(() => _msg = '请输入确认密钥');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSecret, s);
    _secretCtrl.clear();
    setState(() {
      _secretSaved = true;
      _msg = '✅ 密钥已保存（仅存本机，之后不用再填）';
    });
    await _refreshOrders();
  }

  Future<void> _refreshOrders() async {
    final secret = await _secret();
    final backend = kPaymentBackendBaseUrl;
    if (backend.isEmpty) {
      setState(() => _msg = '⚠️ 后端地址未配置');
      return;
    }
    setState(() {
      _loadingOrders = true;
      _msg = null;
    });
    try {
      final resp = await http
          .get(
            Uri.parse('$backend/seller-pending'),
            headers: {'x-confirm-secret': secret},
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final orders = (data['orders'] as List?) ?? [];
        setState(() => _orders = orders.cast<Map<String, dynamic>>());
      } else if (resp.statusCode == 403) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kSecret);
        if (!mounted) return;
        setState(() {
          _secretSaved = false;
          _orders = [];
          _msg = '⚠️ 密钥已失效，请重新输入并保存';
        });
      } else {
        setState(() => _msg = '⚠️ 获取待确认订单失败（HTTP ${resp.statusCode}）');
      }
    } catch (e) {
      setState(() => _msg = '⚠️ 网络错误：$e（检查手机网络 / 后端地址）');
    } finally {
      setState(() => _loadingOrders = false);
    }
  }

  Future<void> _confirm(String orderId) async {
    final secret = await _secret();
    final backend = kPaymentBackendBaseUrl;
    if (backend.isEmpty) {
      setState(() => _msg = '⚠️ 后端地址未配置');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final resp = await http
          .post(
            Uri.parse('$backend/confirm-paid'),
            headers: {
              'content-type': 'application/json',
              'x-confirm-secret': secret,
            },
            body: jsonEncode({'orderId': orderId}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        setState(() => _msg = '✅ 已确认，买家会员将自动开通');
        await _refreshOrders();
        // 同设备确认：立即把该订单权益写回本机，避免买家端轮询已停止导致开不了通。
        try {
          final ent = await http
              .get(
                Uri.parse('$backend/entitlement?orderId=$orderId'),
                headers: backendHeaders(),
              )
              .timeout(const Duration(seconds: 15));
          if (ent.statusCode == 200) {
            final d = jsonDecode(ent.body) as Map<String, dynamic>;
            if (d['isPremium'] == true) {
              await SubscriptionService.instance.activatePurchase(Entitlement(
                isPremium: true,
                source: 'purchase',
                token: d['token'] as String?,
                expireAt: d['expireAt'] == null
                    ? null
                    : DateTime.parse(d['expireAt'] as String),
              ));
              setState(() => _msg = '✅ 已确认，本机会员已开通');
            }
          }
        } catch (_) {
          // 网络异常不影响 confirm 结果，买家端重进付费页会补查。
        }
      } else if (resp.statusCode == 403) {
        setState(() => _msg = '⚠️ 密钥错误');
      } else if (resp.statusCode == 404) {
        setState(() => _msg = '⚠️ 订单不存在或已确认');
        await _refreshOrders();
      } else {
        setState(() => _msg = '⚠️ 确认失败（HTTP ${resp.statusCode}）');
      }
    } catch (e) {
      setState(() => _msg = '⚠️ 网络错误：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String _fmtTime(dynamic ms) {
    if (ms == null) return '';
    try {
      final d = DateTime.fromMillisecondsSinceEpoch(ms is int ? ms : int.parse(ms.toString()));
      return '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('卖家确认'),
        actions: [
          if (_secretSaved)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshOrders,
              tooltip: '刷新',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_secretSaved) ...[
            const Text(
              '首次使用：输入确认密钥（Supabase 项目 Secrets 里的 CONFIRM_SECRET），仅存本机一次，之后不用再填。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secretCtrl,
              decoration: const InputDecoration(
                hintText: '确认密钥',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _saveSecret, child: const Text('保存密钥')),
          ] else ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '待确认订单（买家扫码付款后出现，点「确认」即开通会员）',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove(_kSecret);
                    if (!mounted) return;
                    setState(() {
                      _secretSaved = false;
                      _orders = [];
                      _msg = '请输入新的确认密钥';
                    });
                  },
                  child: const Text('更换密钥'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingOrders) const Center(child: CircularProgressIndicator()),
            if (!_loadingOrders && _orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无待确认订单')),
              ),
            ..._orders.map(
              (o) => Card(
                child: ListTile(
                  title: Text('${o['label'] ?? ''} · ¥${o['priceCny'] ?? ''}'),
                  subtitle: Text(
                    '订单号 ${o['orderId'] ?? ''}\n${_fmtTime(o['createdAt'])}',
                  ),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          onPressed: () => _confirm(o['orderId'] as String),
                          child: const Text('确认'),
                        ),
                ),
              ),
            ),
          ],
          if (_msg != null) ...[
            const SizedBox(height: 14),
            Text(_msg!, style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
