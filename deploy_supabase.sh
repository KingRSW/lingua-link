#!/usr/bin/env bash
# ===================================================================
# LinguaLink 后端一键部署到 Supabase Edge Function
# -------------------------------------------------------------------
# 前置：Node（含 npx）可用；已登录 Supabase 控制台并有一个项目。
#
# 用法（二选一）：
#   A) 环境变量传入（适合让 WorkBuddy 直接跑）：
#      SUPABASE_ACCESS_TOKEN=xxxx SUPABASE_PROJECT_REF=xxxx \
#        ./deploy_supabase.sh
#
#   B) 交互式（自己跑）：
#      ./deploy_supabase.sh
#      按提示粘贴 Personal Access Token 与 Project Ref。
#
# 脚本会自动：
#   1. supabase login（--token 无头登录）
#   2. 建 public.orders 表（Management API 执行 SQL）
#   3. 建 public 存储桶 payqr，并上传 web/pay_qr/wx.jpg、ali.jpg
#   4. 从 .dev.vars 读取密钥并 supabase secrets set（含两张收款码 URL）
#   5. supabase functions deploy lingua-payment
# 最后打印稳定的函数地址，用于重编前端与改手机快捷指令。
# ===================================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---- 读取凭证 ----
if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  read -rs -p "Supabase Personal Access Token: " SUPABASE_ACCESS_TOKEN; echo
fi
if [ -z "${SUPABASE_PROJECT_REF:-}" ]; then
  read -p "Supabase Project Ref: " SUPABASE_PROJECT_REF; echo
fi

REF="$SUPABASE_PROJECT_REF"
PAT="$SUPABASE_ACCESS_TOKEN"
API="https://api.supabase.com/v1"
SB="https://${REF}.supabase.co"
# Supabase CLI 二进制（沙箱里 npx 解析不到 darwin-arm64，改用本地二进制）
if command -v supabase >/dev/null 2>&1; then SB_CLI="supabase"
elif [ -x /Users/kingrsw/.local/bin/supabase ]; then SB_CLI="/Users/kingrsw/.local/bin/supabase"
else SB_CLI="npx --yes supabase@latest"; fi

echo "==> [1/5] supabase login"
$SB_CLI login --token "$PAT"

echo "==> [2/5] 建 orders 表"
SQL=$(cat supabase/migrations/0001_orders.sql)
PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'query': open('supabase/migrations/0001_orders.sql').read()}))")
curl -fsS -X POST "$API/projects/$REF/database/query" \
  -H "Authorization: Bearer $PAT" -H "content-type: application/json" \
  -d "$PAYLOAD" && echo "  orders 表就绪" || echo "  (表可能已存在，继续)"

echo "==> [3/5] 建 payqr 桶并上传收款码"
# 取 service_role 钥匙（Storage 走数据 API，Mgmt API 的 storage/buckets 路径在免费版 404）
KEYS_JSON=$(curl -fsS "$API/projects/$REF/api-keys" -H "Authorization: Bearer $PAT")
SRK=$(printf '%s' "$KEYS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print([k['api_key'] for k in d if k['name']=='service_role'][0])")
curl -fsS -X POST "$SB/storage/v1/bucket" \
  -H "apikey: $SRK" -H "Authorization: Bearer $SRK" -H "content-type: application/json" \
  -d '{"id":"payqr","name":"payqr","public":true}' \
  && echo "  bucket 已建" || echo "  (bucket 可能已存在，继续)"

WX_URL="$SB/storage/v1/object/public/payqr/wx.jpg"
ALI_URL="$SB/storage/v1/object/public/payqr/ali.jpg"

for f in wx ali; do
  src="web/pay_qr/$f.jpg"
  [ -f "$src" ] || { echo "  缺少 $src，跳过"; continue; }
  curl -fsS -X POST "$SB/storage/v1/object/payqr/$f.jpg?upsert=true" \
    -H "apikey: $SRK" -H "Authorization: Bearer $SRK" \
    -H "content-type: image/jpeg" --data-binary "@$src" \
    && echo "  已上传 $src" || echo "  上传 $src 失败"
done

echo "==> [4/5] 注入 secrets"
# 从 .dev.vars 解析 KEY=VALUE（兼容 KEY=value 与 KEY = "value"）
SECRET_ARGS=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue      # 跳过注释
  [[ -z "${line// }" ]] && continue                # 跳过空行
  k=$(echo "$line" | cut -d= -f1 | tr -d '[:space:]')
  v=$(echo "$line" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  [ -z "$k" ] && continue
  [ -z "$v" ] && continue
  # CONFIRM_SECRET 不沿用 dev 值（公开部署会白嫖），单独处理
  [ "$k" = "CONFIRM_SECRET" ] && continue
  SECRET_ARGS+=("$k=$v")
done < .dev.vars

# 固定必须项
SECRET_ARGS+=("PAYMENT_MODE=personal")
SECRET_ARGS+=("PERSONAL_WX_QR=$WX_URL")
SECRET_ARGS+=("PERSONAL_ALI_QR=$ALI_URL")

# CONFIRM_SECRET：默认生成强随机值（公开部署不能沿用 dev 密钥，否则可白嫖）
if [ -n "${SUPABASE_CONFIRM_SECRET:-}" ]; then
  SECRET_ARGS+=("CONFIRM_SECRET=$SUPABASE_CONFIRM_SECRET")
  echo "  使用指定 CONFIRM_SECRET"
elif [ -f supabase/CONFIRM_SECRET.txt ]; then
  SECRET_ARGS+=("CONFIRM_SECRET=$(cat supabase/CONFIRM_SECRET.txt)")
  echo "  复用已保存的 CONFIRM_SECRET"
else
  NEW_SECRET=$(openssl rand -hex 16)
  printf '%s' "$NEW_SECRET" > supabase/CONFIRM_SECRET.txt
  SECRET_ARGS+=("CONFIRM_SECRET=$NEW_SECRET")
  echo "  已生成新 CONFIRM_SECRET 并保存到 supabase/CONFIRM_SECRET.txt"
fi

$SB_CLI secrets set "${SECRET_ARGS[@]}" --project-ref "$REF"

echo "==> [5/5] 部署 Edge Function"
$SB_CLI functions deploy lingua-payment --project-ref "$REF"

echo
echo "========== 部署完成 =========="
echo "函数地址： $SB/functions/lingua-payment"
echo "收款码：   $WX_URL"
echo "           $ALI_URL"
echo "CONFIRM_SECRET： $(cat supabase/CONFIRM_SECRET.txt 2>/dev/null || echo '(见上方日志)')"
echo
echo "下一步："
echo " 1) 重编前端：flutter build web --release --base-href=/<仓库名>/ \\"
echo "      --dart-define=PAYMENT_BACKEND=$SB/functions/lingua-payment"
echo " 2) 改 3 个手机快捷指令："
echo "      - URL 改为 $SB/functions/lingua-payment/confirm-paid"
echo "      - x-confirm-secret 头改为上面的 CONFIRM_SECRET"
