#!/bin/zsh
# ============================================================
# 打包 DEBUG 版本 iOS IPA（未签名，供 Sideloadly / AltStore 重新签名安装）
# 输出: build_output/lingua-link-debug.ipa
# 注意: 沙箱内无法运行 xcodebuild，请在【你自己的终端】执行本脚本。
#       本脚本只负责生成 IPA；用 Sideloadly/AltStore 安装时会用你的
#       免费 Apple ID 自动重新签名（7 天有效，到期重装即可）。
# ============================================================
set -e

# ---- 项目路径（已更新为当前目录）----
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
log "获取依赖"
flutter pub get

# ---------- iOS debug IPA（未签名）----------
log "[1/1] 构建 iOS debug（--no-codesign）..."
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
  exit 1
fi

# 打包成未签名 IPA（Sideloadly/AltStore 会重新签名）
rm -rf Payload
mkdir Payload
cp -r "$APP_PATH" Payload/
rm -rf Payload/Runner.app/_CodeSignature 2>/dev/null || true
rm -rf Payload/Runner.app/Frameworks/*/_CodeSignature 2>/dev/null || true
rm -f "$OUTPUT_DIR/lingua-link-debug.ipa"
zip -r "$OUTPUT_DIR/lingua-link-debug.ipa" Payload >/dev/null
rm -rf Payload
ok "IPA -> $OUTPUT_DIR/lingua-link-debug.ipa ($(du -h "$OUTPUT_DIR/lingua-link-debug.ipa" | cut -f1))"

echo ""
log "完成。下一步：用 Sideloadly / AltStore 打开上面的 IPA，选择你的免费 Apple ID 重新签名安装。"
