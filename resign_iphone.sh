#!/usr/bin/env bash
# ============================================================================
# resign_iphone.sh — LinguaLink 一键重签并装回 iPhone（免费 Apple ID，7 天有效）
# ----------------------------------------------------------------------------
# 用法：
#   bash resign_iphone.sh
# 前提：
#   - 手机解锁，且与 Mac 在同一 Wi-Fi（或 USB 连着）
#   - 免费 Apple ID(quanwei / KDX2FPABY9) 仍在 Xcode 登录态
# 说明：每 7 天跑一次即可让 App 持续可用，无需花钱、无需开 Xcode 手动操作。
# ============================================================================
set -e

PROJ="/Users/kingrsw/lingua link"
UDID="00008150-000A4951210A401C"
BACKEND="https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment"

cd "$PROJ" || { echo "❌ 找不到项目目录 $PROJ"; exit 1; }

echo "▶ 检查设备是否在线..."
if ! xcrun devicectl list devices 2>/dev/null | grep -q "available (paired)"; then
  echo "⚠️  手机不可达：请解锁 iPhone 并连同一 Wi-Fi（或插 USB），然后重跑本脚本。"
  exit 1
fi

echo "▶ 构建 iOS release（自动用免费团队 KDX2FPABY9 签名）..."
flutter build ios --release \
  --dart-define=PAYMENT_BACKEND="$BACKEND" \
  --dart-define=PAYMENT_DEV=false

echo "▶ 无线装回 iPhone（devicectl）..."
xcrun devicectl device install app --device "$UDID" build/ios/iphoneos/Runner.app

echo ""
echo "✅ 重签完成！App 有效期已刷新为 7 天。"
echo "   下次到期前再跑一次本脚本即可（建议让定时任务自动跑）。"
