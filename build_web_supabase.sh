#!/bin/zsh
# ============================================================
# 一键构建并部署 Lingua Link 网页版（后端 = Supabase Edge Function）
#
# 与 deploy_gh_pages.sh 的唯一区别：把 Supabase 后端地址烤进构建，
# 并关闭 DEV 模式（PAYMENT_DEV=false），这样上线后真实下单 / 确认 / 权益生效。
#
# 用法：
#   ./build_web_supabase.sh <github用户名> <仓库名>
#   例：./build_web_supabase.sh KingRSW lingua-link
#
# 可选环境变量（不传也能跑；apikey 头网关默认放行，不强制）：
#   SUPABASE_ANON_KEY=eyJ...   把 Supabase anon key 烤进前端，给所有后端请求带 apikey 头
#
# 说明：
#   - base-href 自动设为 /<仓库名>/（项目页：https://<用户>.github.io/<仓库名>/）
#   - 推送到 gh-pages 分支；之后去 Settings → Pages 选 gh-pages / root
#   - 后端稳定地址（已确认常驻可用）：
#       https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment
# ============================================================
set -e

cd "$(dirname "$0")"
export PATH="/Users/kingrsw/develop/flutter/bin:$PATH"

USER="${1:-KingRSW}"
REPO="${2:-lingua-link}"

PAYMENT_BACKEND="${PAYMENT_BACKEND:-https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment}"
ANON_KEY="${SUPABASE_ANON_KEY:-}"

echo "==> 构建网页版（base-href=/$REPO/，后端=$PAYMENT_BACKEND）"

BUILD_ARGS=(
  build web --release
  --base-href="/$REPO/"
  --dart-define=PAYMENT_BACKEND="$PAYMENT_BACKEND"
  --dart-define=PAYMENT_DEV=false
)
if [ -n "$ANON_KEY" ]; then
  BUILD_ARGS+=(--dart-define=SUPABASE_ANON_KEY="$ANON_KEY")
fi

flutter "${BUILD_ARGS[@]}"

TMP=$(mktemp -d)
cp -r build/web/. "$TMP/"

echo "==> 初始化 gh-pages 分支并推送"
cd "$TMP"
git init -q
git checkout -b gh-pages
git add -A
git commit -qm "Deploy Lingua Link web (Supabase backend) $(date +%Y%m%d-%H%M%S)"
git remote add origin "https://github.com/$USER/$REPO.git"
git push -f origin gh-pages

echo ""
echo "✅ 部署完成！"
echo "   1) 打开 https://github.com/$USER/$REPO → Settings → Pages"
echo "   2) Source 选 gh-pages 分支 / root，保存"
echo "   3) 几分钟后访问: https://$USER.github.io/$REPO/"
rm -rf "$TMP"
