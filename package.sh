#!/usr/bin/env bash
#
# package.sh — Flutter 一键出包脚本 (macOS / Linux)
# ----------------------------------------------------------------------------
# 支持目标:
#   ipa   未签名 iOS 安装包 (flutter build ipa --no-codesign) —— 爱思助手侧载用
#   apk   Android 安装包 (按 ABI 拆分: arm64-v8a / armeabi-v7a / x86_64)
#   dmg   macOS 磁盘镜像 (flutter build macos + create-dmg / hdiutil 兜底)
#   exe   Windows 安装包 —— 仅 Windows 可用，Mac 上会提示你用 package.ps1
#
# 用法:
#   ./package.sh all      # 在当前系统能出的包，全部出 (Mac: ipa+apk+dmg)
#   ./package.sh ipa      # 只出 iOS 未签名 IPA
#   ./package.sh apk      # 只出 Android APK
#   ./package.sh dmg      # 只出 macOS DMG
#   ./package.sh clean    # 清掉 build/ 与 dist/
#   ./package.sh --help   # 看这个
#
# 出包位置: 项目根目录下的 dist/<app>-<版本>-<平台>.{ipa,apk,dmg}
# ----------------------------------------------------------------------------

set -uo pipefail

# ====== 可改配置区（一般不用动，留空即自动从 pubspec 读） ======
OUTPUT_DIR="${OUTPUT_DIR:-dist}"     # 出包目录
APP_NAME="${APP_NAME:-}"            # 留空=自动读 pubspec 的 name
VERSION="${VERSION:-}"              # 留空=自动读 pubspec 的 version
BUILD_NUMBER="${BUILD_NUMBER:-}"    # 留空=自动读 pubspec 的 build number
IPA_NO_CODESIGN="${IPA_NO_CODESIGN:-true}"   # true=出未签名 IPA(爱思助手侧载)
# ===============================================================

# ---- 颜色日志 ----
if [ -t 1 ]; then
  C_R="\033[31m"; C_G="\033[32m"; C_Y="\033[33m"; C_B="\033[34m"; C_N="\033[0m"
else
  C_R=""; C_G=""; C_Y=""; C_B=""; C_N=""
fi
log()  { printf "${C_G}[OK]${C_N}   %s\n" "$*"; }
info() { printf "${C_B}[..]${C_N}   %s\n" "$*"; }
warn() { printf "${C_Y}[!!]${C_N}   %s\n" "$*"; }
die()  { printf "${C_R}[XX]${C_N}   %s\n" "$*" >&2; exit 1; }

OS="$(uname -s)"

# ---- 前置检查 ----
[ -f "pubspec.yaml" ] || die "当前目录不是 Flutter 项目 (找不到 pubspec.yaml)。请把 package.sh 放到 Flutter 项目根目录再跑。"
command -v flutter >/dev/null 2>&1 || die "找不到 flutter 命令。请先安装 Flutter 并 source 环境 (如 export PATH=.../flutter/bin:\$PATH)。"

require_tool() { command -v "$1" >/dev/null 2>&1 || die "缺少依赖: $1 —— $2"; }

# ---- 读取版本/名称 ----
read_meta() {
  [ -z "$APP_NAME" ] && APP_NAME="$(grep -m1 '^name:' pubspec.yaml | sed 's/^name:[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$APP_NAME" ] && die "无法从 pubspec.yaml 读取 name，请在脚本顶部手动设置 APP_NAME。"
  if [ -z "$VERSION" ]; then
    local pv
    pv="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
    VERSION="${pv%%+*}"
    [ -z "$BUILD_NUMBER" ] && BUILD_NUMBER="${pv##*+}"
    [ "$BUILD_NUMBER" = "$pv" ] && BUILD_NUMBER=""
  fi
  info "项目: $APP_NAME  版本: ${VERSION}${BUILD_NUMBER:++$BUILD_NUMBER}  (系统: $OS)"
}

# ---- 各平台构建 ----
build_ipa() {
  info "构建 iOS IPA (no-codesign=$IPA_NO_CODESIGN) ..."
  [ "$OS" = "Darwin" ] || { warn "IPA 只能在 macOS 上构建，已跳过。"; return; }
  local args=(build ipa --release)
  [ "$IPA_NO_CODESIGN" = "true" ] && args+=(--no-codesign)
  flutter "${args[@]}" || die "flutter build ipa 失败"
  local src
  src="$(ls build/ios/ipa/*.ipa 2>/dev/null | head -n1)"
  [ -n "$src" ] || die "没找到 build/ios/ipa/*.ipa"
  mkdir -p "$OUTPUT_DIR"
  cp "$src" "$OUTPUT_DIR/${APP_NAME}-${VERSION}-ios.ipa"
  log "IPA -> $OUTPUT_DIR/${APP_NAME}-${VERSION}-ios.ipa"
}

build_apk() {
  info "构建 Android APK (按 ABI 拆分) ..."
  flutter build apk --release --split-per-abi || die "flutter build apk 失败"
  mkdir -p "$OUTPUT_DIR"
  local f found=0
  for f in build/app/outputs/flutter-apk/*.apk; do
    [ -e "$f" ] || continue
    local arch
    case "$f" in
      *arm64-v8a*)   arch="arm64" ;;
      *armeabi-v7a*) arch="armeabi" ;;
      *x86_64*)      arch="x86_64" ;;
      *)             arch="universal" ;;
    esac
    cp "$f" "$OUTPUT_DIR/${APP_NAME}-${VERSION}-android-${arch}.apk"
    log "APK($arch) -> $OUTPUT_DIR/${APP_NAME}-${VERSION}-android-${arch}.apk"
    found=1
  done
  [ "$found" = "1" ] || die "没找到 build/app/outputs/flutter-apk/*.apk"
}

build_dmg() {
  info "构建 macOS DMG ..."
  [ "$OS" = "Darwin" ] || { warn "DMG 只能在 macOS 上构建，已跳过。"; return; }
  flutter build macos --release || die "flutter build macos 失败"
  local app="build/macos/Build/Products/Release/${APP_NAME}.app"
  [ -e "$app" ] || die "没找到 $app"
  mkdir -p "$OUTPUT_DIR"
  local out="$OUTPUT_DIR/${APP_NAME}-${VERSION}-macos.dmg"
  if command -v create-dmg >/dev/null 2>&1; then
    info "用 create-dmg 打包 ..."
    create-dmg --overwrite "$out" "$app" >/dev/null 2>&1 \
      || hdiutil create -volname "$APP_NAME" -fs HFS+ -srcfolder "$app" -format UDZO -ov "$out"
  else
    warn "未安装 create-dmg (brew install create-dmg 体验更好)，用 hdiutil 兜底。"
    hdiutil create -volname "$APP_NAME" -fs HFS+ -srcfolder "$app" -format UDZO -ov "$out"
  fi
  log "DMG -> $out"
}

build_exe() {
  warn "EXE 无法在 macOS/Linux 上交叉编译 (Flutter 限制)。"
  warn "请到 Windows 机器上用配套脚本:  .\\package.ps1 all"
  warn "Mac 上已为你跳过 EXE。若要纯 Windows 一键，把 package.ps1 拷过去即可。"
}

clean() {
  info "清理 build/ 与 $OUTPUT_DIR/ ..."
  rm -rf build "$OUTPUT_DIR"
  log "已清理"
}

# ---- 入口 ----
usage() { sed -n '3,22p' "$0"; }

main() {
  local target="${1:-all}"
  case "$target" in
    --help|-h|help) usage; exit 0 ;;
  esac
  read_meta
  case "$target" in
    all)
      build_apk
      [ "$OS" = "Darwin" ] && { build_ipa; build_dmg; } || build_exe
      ;;
    ipa) build_ipa ;;
    apk) build_apk ;;
    dmg) build_dmg ;;
    exe) build_exe ;;
    clean) clean ;;
    *) die "未知目标: $target  (使用 ./package.sh --help 查看用法)" ;;
  esac
  log "全部完成。出包目录: $OUTPUT_DIR/"
}

main "$@"
