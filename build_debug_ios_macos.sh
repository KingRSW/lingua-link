#!/bin/zsh
# ============================================================
# 打包 DEBUG 版本：iOS 未签名 IPA + macOS DMG（不含 Android）
# 输出目录：build_output/
# ============================================================
set -e

cd "/Users/kingrsw/lingua link"
export PATH="/Users/kingrsw/develop/flutter/bin:$PATH"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log(){ echo -e "${BLUE}==>${NC} $1"; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }

OUTPUT_DIR="$(pwd)/build_output"
mkdir -p "$OUTPUT_DIR"

log "Flutter 版本"
flutter --version
log "启用 macOS 桌面支持"
flutter config --enable-macos-desktop >/dev/null 2>&1 || true
log "获取依赖"
flutter pub get

# ---------- 1. iOS IPA (debug, 未签名) ----------
log "[1/2] 构建 iOS debug 未签名 IPA ..."
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter build ios --debug --no-codesign

APP_PATH="build/ios/Debug-iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH=$(find build/ios -name Runner.app -path '*Debug*' -maxdepth 4 2>/dev/null | head -1)
fi
if [ ! -d "$APP_PATH" ]; then
  warn "Runner.app 未找到，iOS 构建可能失败"
else
  rm -rf Payload
  mkdir Payload
  cp -r "$APP_PATH" Payload/
  rm -rf Payload/Runner.app/_CodeSignature
  rm -rf Payload/Runner.app/Frameworks/*/_CodeSignature
  codesign -s - --force Payload/Runner.app/Frameworks/* 2>/dev/null || true
  zip -r "$OUTPUT_DIR/lingua-link-debug.ipa" Payload >/dev/null
  rm -rf Payload
  ok "IPA -> $OUTPUT_DIR/lingua-link-debug.ipa ($(du -h "$OUTPUT_DIR/lingua-link-debug.ipa" | cut -f1))"
fi

# ---------- 2. macOS DMG (debug) ----------
log "[2/2] 构建 macOS debug 应用并打包 DMG ..."
flutter build macos --debug
MAC_APP="build/macos/Build/Products/Debug/translate_app.app"
if [ ! -d "$MAC_APP" ]; then
  MAC_APP=$(find build/macos -name '*.app' -path '*Debug*' -maxdepth 5 2>/dev/null | head -1)
fi
if [ -d "$MAC_APP" ]; then
  codesign --force --deep --sign - "$MAC_APP" 2>/dev/null || true
  DMG="$OUTPUT_DIR/lingua-link-debug.dmg"
  hdiutil create -volname "lingua link" -srcfolder "$MAC_APP" -ov -format UDZO "$DMG"
  ok "DMG -> $DMG ($(du -h "$DMG" | cut -f1))"
else
  warn "macOS .app 未生成"
fi

echo ""
log "打包完成，输出目录: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
