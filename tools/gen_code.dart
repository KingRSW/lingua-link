// 生成解锁码给赞助者。
// 运行：dart run tools/gen_code.dart
// 校验算法必须与 lib/subscription_service.dart 的 _checksum 保持一致。
import 'dart:io';
import 'dart:math';

const String _salt = 'LinguaLink-2026-StaticSite';

String _checksum(String seed) {
  int h = 0x811c9dc5;
  final s = seed + _salt;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  h = (h ^ (h >> 13)) & 0xFFFFFFFF;
  h = (h * 0x5bd1e995) & 0xFFFFFFFF;
  h = (h ^ (h >> 15)) & 0xFFFFFFFF;
  final hex = h.toRadixString(36).toUpperCase().padLeft(7, '0');
  return hex.substring(0, 6);
}

String _randMiddle(Random r) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

void main() {
  final r = Random();
  print('=== 解锁码（发给赞助者，每人一个）===');
  for (int i = 0; i < 3; i++) {
    final m = _randMiddle(r);
    print('  LINGUA-$m-${_checksum(m)}');
  }
  print('格式：LINGUA-<6位>-<6位校验和>，用户在「高级功能订阅」里输入即解锁。');
}
