#!/bin/zsh
# ============================================================
# 打包 macOS RELEASE 版（.app + DMG），本地可直接用，无需手机签名
# 输出: build_output/lingua-link-release.dmg
#
# 与 iOS 不同：macOS 不需要 Apple 开发者账号签名即可在本机运行
# （release 版同样是 AOT 编译，跟终端无关，关掉终端照常运行）。
# ============================================================
set -e

cd "/Users/kingrsw/lingua link"
export PATH="/Users/kingrsw/develop/flutter/bin:$PATH"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}==>${NC} $1"; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }

OUTPUT_DIR="$(pwd)/build_output"
mkdir -p "$OUTPUT_DIR"

log "Flutter 版本"
flutter --version
log "获取依赖"
flutter pub get

# ---------- macOS release ----------
log "[1/1] 构建 macOS release ..."
flutter build macos --release

MAC_APP="build/macos/Build/Products/Release/translate_app.app"
if [ ! -d "$MAC_APP" ]; then
  MAC_APP=$(find build/macos -name '*.app' -path '*Release*' -maxdepth 5 2>/dev/null | head -1)
fi
if [ ! -d "$MAC_APP" ]; then
  echo "❌ .app 未生成，构建可能失败"
  exit 1
fi

# 本地运行用：ad-hoc 签名一下，避免 Gatekeeper 拦截
codesign --force --deep --sign - "$MAC_APP" 2>/dev/null || true

# 打包成 DMG，方便拷贝/分发
DMG="$OUTPUT_DIR/lingua-link-release.dmg"
rm -f "$DMG"
hdiutil create -volname "lingua link" -srcfolder "$MAC_APP" -ov -format UDZO "$DMG"
ok "DMG -> $DMG ($(du -h "$DMG" | cut -f1))"

echo ""
log "完成。把 DMG 里的 lingua link.app 拖到 应用程序 即可使用。"
log "（显示名已是 lingua link；.app 文件名仍是 translate_app，不影响使用。）"
