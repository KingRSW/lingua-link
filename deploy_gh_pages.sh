#!/bin/zsh
# ============================================================
# 一键部署 Lingua Link 网页版到 GitHub Pages
#
# 前置条件：
#   1. 你已在 github.com 新建一个空仓库（例如 lingua-link）
#   2. 本机已配置 git 且能推送到该仓库（SSH 或 HTTPS + token）
#   3. Flutter 已安装（脚本会临时把 flutter 加入 PATH）
#
# 用法：
#   ./deploy_gh_pages.sh <github用户名> <仓库名>
#   例：./deploy_gh_pages.sh kingrsw lingua-link
#
# 说明：
#   - 默认按「项目页」部署，base-href 设为 /<仓库名>/（访问地址 https://<用户>.github.io/<仓库名>/）
#   - 如果你用的是「用户/组织页」（仓库名必须是 <用户名>.github.io），请改用：
#       flutter build web --release --base-href="/"   再手动推送 build/web 到 gh-pages
#   - 推送到 gh-pages 分支后，去仓库 Settings → Pages 选 gh-pages / root 即可
# ============================================================
set -e

cd "$(dirname "$0")"
export PATH="/Users/kingrsw/develop/flutter/bin:$PATH"

USER="$1"
REPO="$2"
if [ -z "$USER" ] || [ -z "$REPO" ]; then
  echo "用法: ./deploy_gh_pages.sh <github用户名> <仓库名>"
  exit 1
fi

echo "==> 重新构建网页版（base-href=/$REPO/）"
flutter build web --release --base-href="/$REPO/"

TMP=$(mktemp -d)
cp -r build/web/. "$TMP/"

echo "==> 初始化 gh-pages 分支并推送"
cd "$TMP"
git init -q
git checkout -b gh-pages
git add -A
git commit -qm "Deploy Lingua Link web $(date +%Y%m%d-%H%M%S)"
git remote add origin "https://github.com/$USER/$REPO.git"
git push -f origin gh-pages

echo ""
echo "✅ 部署完成！"
echo "   1) 打开 https://github.com/$USER/$REPO → Settings → Pages"
echo "   2) Source 选 gh-pages 分支 / root，保存"
echo "   3) 几分钟後访问: https://$USER.github.io/$REPO/"
rm -rf "$TMP"
