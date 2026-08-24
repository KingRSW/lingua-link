#!/usr/bin/env bash
# ============================================================================
# sign.sh — 通用 iOS IPA 签名 / 打包工具
# ----------------------------------------------------------------------------
# 两种模式:
#   A) ad-hoc 模式 (默认, 不给证书):
#      只给主 app 打 ad-hoc 占位签名, Framework 保持未签, 干净打包
#      —— 给爱思助手/AltStore 用免费 Apple ID 重签时, 避免 "安装包不完整"
#   B) cert 模式 (显式给 .p12 + .mobileprovision, 或 --identity + .mobileprovision):
#      用证书把 Framework + 主 app 全签好, 直接出可装包 (不走爱思助手重签)
#      --identity 可直接用 Mac 登录钥匙串里已有的真实 Apple 证书 (如免费 Apple ID 的开发证书)
#
# 用法:
#   sign.sh [选项] <ipa> [证书目录或 ad-hoc]
#
# 选项:
#   --fix-id            cert 模式: AppID 对不上时自动改写 IPA 的 bundle ID 为证书的 AppID
#   --out <dir>         签名结果输出目录 (默认 = IPA 所在目录)
#   --p12 <file>        cert 模式: 指定 .p12 (购买证书, 如 iosxb.cn)
#   --identity <sha1|名称>  cert 模式: 直接用登录钥匙串里的真实 Apple 证书 (免导 p12)
#   --prov <file>       cert 模式: 指定 .mobileprovision
#   --password <pw>      p12 密码 (默认: 环境变量 P12_PASSWORD / 文件名 密码_xxx / 兜底 iosxb.cn)
#   --no-verify         跳过验签打印
#   -h | --help         帮助
# ============================================================================

set -eo pipefail

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }
die()   { red "$*"; exit 1; }

# 生成一个"伪 ad-hoc 描述文件"并嵌入 app, 修爱思助手"安装包不完整"
# 用 openssl 自签证书 + plist, 然后用 smime 包成 iOS 认识的 CMS/DER 结构
make_adhoc_prov() {
  local app_dir="$1" bundle_id="$2"
  local out="$app_dir/embedded.mobileprovision"
  local tmpdir team_id="ZZZZZZZZZZ"
  tmpdir=$(mktemp -d -t adhocprov)
  # 1. 临时自签证书 (cert + key, 10 年)
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$tmpdir/key.pem" -out "$tmpdir/cert.pem" \
    -days 3650 -nodes -subj "/CN=Adhoc Provisioning" >/dev/null 2>&1 \
    || { rm -rf "$tmpdir"; return 1; }
  # 2. 写符合 iOS 期望的 plist (结构上像"单设备 ad-hoc 开发描述文件")
  # 关键: 去掉 ProvisionsAllDevices (这是企业证书专属, 会触发爱思助手"越狱版"标记)
  # 改成 ProvisionedDevices 数组 (单个 dummy UDID), 看起来更像免费 Apple ID 的开发描述
  cat > "$tmpdir/profile.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AppIDName</key><string>Adhoc Sideload</string>
    <key>ApplicationIdentifierPrefix</key><array><string>${team_id}</string></array>
    <key>CreationDate</key><date>2024-01-01T00:00:00Z</date>
    <key>ExpirationDate</key><date>2099-12-31T00:00:00Z</date>
    <key>Entitlements</key><dict>
        <key>application-identifier</key><string>${team_id}.${bundle_id}</string>
        <key>get-task-allow</key><true/>
        <key>keychain-access-groups</key><array><string>${team_id}.*</string></array>
    </dict>
    <key>Name</key><string>${bundle_id}</string>
    <key>ProvisionedDevices</key><array><string>00000000-0000000000000000</string></array>
    <key>TeamIdentifier</key><array><string>${team_id}</string></array>
    <key>TeamName</key><string>Adhoc Team</string>
    <key>UUID</key><string>$(uuidgen)</string>
    <key>Version</key><integer>1</integer>
</dict>
</plist>
EOF
  # 3. openssl smime 把它包成 CMS/DER (iOS 识别的描述文件格式)
  if openssl smime -sign \
      -in "$tmpdir/profile.plist" -out "$out" \
      -signer "$tmpdir/cert.pem" -inkey "$tmpdir/key.pem" \
      -certfile "$tmpdir/cert.pem" \
      -outform DER -nodetach >/dev/null 2>&1 && [ -s "$out" ]; then
    rm -rf "$tmpdir"
    return 0
  else
    rm -rf "$tmpdir"
    return 1
  fi
}

IPA=""
CERT_DIR="."
P12=""
IDENTITY=""
PROV=""
PASSWORD=""
FIX_ID=0
OUT_DIR=""
show_help=0
VERIFY=1

while [ $# -gt 0 ]; do
  case "$1" in
    --fix-id)    FIX_ID=1 ;;
    --out)       OUT_DIR="$2"; shift ;;
    --p12)       P12="$2"; shift ;;
    --identity)  IDENTITY="$2"; shift ;;
    --prov)      PROV="$2"; shift ;;
    --password)  PASSWORD="$2"; shift ;;
    --no-verify) VERIFY=0 ;;
    -h|--help)   show_help=1 ;;
    *)  [ -z "$IPA" ] && IPA="$1" || CERT_DIR="$1" ;;
  esac
  shift
done

if [ "$show_help" = 1 ]; then sed -n '3,28p' "$0"; exit 0; fi
[ -z "$IPA" ] && die "用法: $0 [选项] <ipa> [证书目录]  (--help 看详情)"
[ -f "$IPA" ] || die "找不到 IPA: $IPA"

# 是否在 cert 模式: 只有显式传 --p12 / --prov / --identity 才算
CERT_MODE=0
if [ -n "$P12" ] || [ -n "$PROV" ] || [ -n "$IDENTITY" ]; then CERT_MODE=1; fi

WORK=$(mktemp -d -t signipa)
trap 'rm -rf "$WORK"' EXIT

# ----- 解 IPA -----
mkdir -p "$WORK/payload"
unzip -q "$IPA" -d "$WORK/payload"
APP_DIR=$(find "$WORK/payload/Payload" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP_DIR" ] || die "IPA 里没找到 .app"
APP_BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_DIR/Info.plist")
APP_NAME=$(basename "$APP_DIR" .app)
blue "目标 App:  $APP_NAME ($APP_BUNDLE)"

# ============================================================
# 模式 A: ad-hoc (爱思助手/AltStore 重签场景)
# ============================================================
if [ "$CERT_MODE" = 0 ]; then
  blue "模式: ad-hoc 占位签名 (Framework 先剥真签名再强制 ad-hoc, 防重签冲突)"
  if [ -d "$APP_DIR/Frameworks" ]; then
    for fw in "$APP_DIR/Frameworks"/*; do
      [ -e "$fw" ] || continue
      # 先剥离源包里可能残留的真(分发/企业)签名, 再强制打 ad-hoc 占位
      codesign --remove-signature "$fw" >/dev/null 2>&1 || true
      codesign --force --sign - --timestamp=none "$fw" >/dev/null 2>&1 || true
    done
  fi
  # 主 app 打 ad-hoc 占位
  codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 \
    || die "ad-hoc 占位签名失败"
  codesign --verify --strict "$APP_DIR" >/dev/null 2>&1 \
    || blue "⚠️  主 app 占位签名校验未过, 但爱思助手一般会重签"
  # 缺 embedded.mobileprovision → 生成伪 ad-hoc 描述文件, 修"安装包不完整"
  if [ ! -f "$APP_DIR/embedded.mobileprovision" ]; then
    blue "源 IPA 没带 embedded.mobileprovision, 生成伪 ad-hoc 描述文件"
    if make_adhoc_prov "$APP_DIR" "$APP_BUNDLE"; then
      green "✓ 已嵌入伪 ad-hoc 描述文件"
    else
      blue "⚠️  伪描述文件生成失败, 爱思助手可能仍报"安装包不完整""
    fi
  fi
  MODE_TAG="adhoc"
else
  # ==========================================================
  # 模式 B: cert 全签
  # ==========================================================
  [ -z "$PROV" ] && PROV=$(find "$CERT_DIR" -maxdepth 2 -name "*.mobileprovision" 2>/dev/null | head -1)
  [ -n "$PROV" ] || die "cert 模式需要 .mobileprovision (用 --prov 指定)"
  [ -f "$PROV" ] || die "找不到描述文件: $PROV"
  blue "描述:  $(basename "$PROV")"

  # 拿签名身份有两种方式:
  #   A) --p12  → 临时钥匙串导入 (iosxb.cn 这类购买证书)
  #   B) --identity (SHA1 或名称) → 直接用登录钥匙串里已有的真实 Apple 证书
  if [ -n "$P12" ]; then
    [ -z "$IDENTITY" ] && blue "证书:  $(basename "$P12")"
    # 密码
    [ -z "$PASSWORD" ] && PASSWORD="${P12_PASSWORD:-}"
    [ -z "$PASSWORD" ] && PASSWORD=$(basename "$P12" | sed -nE 's/.*(密码|pwd)[_-]([^)]+).*/\2/p' | head -1)
    [ -z "$PASSWORD" ] && PASSWORD="iosxb.cn"
    [ -z "$IDENTITY" ] && green "p12 密码: $PASSWORD"
    # 临时钥匙串 + OpenSSL 绕过 macOS PKCS12 MAC 限制
    KC="$WORK/sign.keychain"; KC_PW=$(openssl rand -hex 16)
    security create-keychain -p "$KC_PW" "$KC" >/dev/null
    security set-keychain-settings -lut 21600 "$KC" >/dev/null
    security unlock-keychain -p "$KC_PW" "$KC" >/dev/null
    security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"') >/dev/null
    openssl pkcs12 -in "$P12" -passin pass:"$PASSWORD" -nodes -nokeys -out "$WORK/cert.pem" 2>/dev/null
    openssl pkcs12 -in "$P12" -passin pass:"$PASSWORD" -nodes -nocerts -out "$WORK/key.pem" 2>/dev/null
    [ -s "$WORK/key.pem" ] && grep -q "PRIVATE KEY" "$WORK/key.pem" || die "p12 解密失败: 密码不对或文件损坏"
    security import "$WORK/cert.pem" -k "$KC" -T /usr/bin/codesign >/dev/null 2>&1 || true
    security import "$WORK/key.pem"  -k "$KC" -T /usr/bin/codesign >/dev/null 2>&1 || true
    if [ -z "$IDENTITY" ]; then
      IDENTITY=$(security find-identity -v -p codesigning "$KC" 2>/dev/null \
        | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) ".*"/\1/p' | head -1)
    fi
  elif [ -n "$IDENTITY" ]; then
    blue "签名身份: 直接用登录钥匙串里的 $IDENTITY"
  else
    die "cert 模式需要 .p12 (--p12) 或 钥匙串身份 (--identity)"
  fi
  [ -n "$IDENTITY" ] || die "没找到可用的签名身份"
  green "签名身份: $IDENTITY"

  security cms -D -i "$PROV" -o "$WORK/prov.plist" >/dev/null
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$WORK/prov.plist" > "$WORK/entitlements.plist"
  PROV_BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$WORK/prov.plist" \
    | sed 's/^[A-Z0-9]*\.//')
  blue "描述文件 AppID: $PROV_BUNDLE"

  if [ "$APP_BUNDLE" != "$PROV_BUNDLE" ]; then
    if [ "$FIX_ID" = 1 ]; then
      blue "⚠️  --fix-id: 改写 IPA bundle ID 为 $PROV_BUNDLE"
      /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROV_BUNDLE" "$APP_DIR/Info.plist"
      APP_BUNDLE="$PROV_BUNDLE"
    else
      die "❌ bundle ID 不匹配: App=$APP_BUNDLE  vs  Provision=$PROV_BUNDLE
   方案A: 让卖家按 $APP_BUNDLE 重发描述文件
   方案B: 加 --fix-id 改写 IPA 的 bundle ID"
    fi
  fi

  cp "$PROV" "$APP_DIR/embedded.mobileprovision"

  # 签 Framework (从内向外), 再签主 app
  if [ -d "$APP_DIR/Frameworks" ]; then
    for FW in $(find "$APP_DIR/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | sort); do
      codesign --force --sign "$IDENTITY" --generate-entitlement-der --timestamp=none "$FW" 2>&1 | sed 's/^/  /'
    done
  fi
  codesign --force --sign "$IDENTITY" \
    --entitlements "$WORK/entitlements.plist" \
    --generate-entitlement-der --preserve-metadata=identifier,flags \
    "$APP_DIR" 2>&1 | sed 's/^/  /'
  MODE_TAG="signed"
fi

# ----- 干净重新打包 (从 Payload 父目录 zip, 保留 Payload/ 前缀) -----
[ -z "$OUT_DIR" ] && OUT_DIR="$(dirname "$IPA")"
mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$(basename "$IPA" .ipa)-${MODE_TAG}.ipa"
rm -f "$OUT"
( cd "$WORK/payload" && zip -qr "$OUT" Payload -x "*.DS_Store" "__MACOSX/*" )
green "✅ 已生成: $OUT"

if [ "$VERIFY" = 1 ]; then
  echo ""
  blue "--- 验签 ---"
  codesign -dv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature size|Signed Time" || true
fi
green "完成。"
