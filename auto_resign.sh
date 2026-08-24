#!/usr/bin/env bash
# ============================================================================
# auto_resign.sh — 检测免费证书是否满 7 天，满了才自动重签 LinguaLink
# ----------------------------------------------------------------------------
# 设计：
#   - 用状态文件 .resign_last 记录上次【成功】重签的时间戳。
#   - 距上次 < 7 天 → 直接跳过（打印剩余天数），不浪费时间。
#   - 距上次 >= 7 天（或无记录）→ 检查手机在线 → flutter build → 无线装回；
#     成功才更新时间戳，失败（手机不可达等）不更新 → 下次再试（自愈）。
#   - 所有动作写 resign.log，方便排查。
# 由 launchd / 定时任务每天跑一次即可；它自己判断"是否到 7 天"。
# ============================================================================
export PATH="/Users/kingrsw/develop/flutter/bin:$PATH"

PROJ="/Users/kingrsw/lingua link"
UDID="00008150-000A4951210A401C"
BACKEND="https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment"
STATE="$PROJ/.resign_last"
LOG="$PROJ/resign.log"
INTERVAL=$(( 7 * 24 * 3600 ))   # 7 天（秒）
NOW=$(date +%s)

log() { echo "$(date '+%Y-%m-%d %H:%M') $*" | tee -a "$LOG"; }

# ---- 1) 是否到 7 天 ----
if [ -f "$STATE" ]; then
  LAST=$(cat "$STATE" 2>/dev/null || echo 0)
  [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
  ELAPSED=$(( NOW - LAST ))
  if [ "$ELAPSED" -lt "$INTERVAL" ]; then
    LEFT=$(( (INTERVAL - ELAPSED) / 86400 ))
    HRS=$(( ((INTERVAL - ELAPSED) % 86400) / 3600 ))
    log "✅ 尚未到 7 天（还剩约 ${LEFT} 天 ${HRS} 小时），跳过重签。"
    exit 0
  fi
  log "⏰ 距上次重签已超 7 天，开始重签..."
else
  log "⏰ 无重签记录，首次执行，开始重签..."
fi

# ---- 2) 手机在线检查 ----
if ! xcrun devicectl list devices 2>/dev/null | grep -q "available (paired)"; then
  log "⚠️ 手机不可达（需解锁 + 同 Wi-Fi / USB），本次跳过，下次再试。"
  exit 1
fi

# ---- 3) 构建 + 安装 ----
cd "$PROJ" || exit 1
log "▶ flutter build ios --release ..."
if ! flutter build ios --release \
  --dart-define=PAYMENT_BACKEND="$BACKEND" \
  --dart-define=PAYMENT_DEV=false >>"$LOG" 2>&1; then
  log "❌ 构建失败，保留旧记录，下次再试。"
  exit 1
fi

log "▶ 无线装回 iPhone ..."
if xcrun devicectl device install app --device "$UDID" build/ios/iphoneos/Runner.app >>"$LOG" 2>&1; then
  echo "$NOW" > "$STATE"
  log "✅ 重签完成，有效期刷新为 7 天。"
  exit 0
else
  log "❌ 安装失败，保留旧记录，下次再试。"
  exit 1
fi
