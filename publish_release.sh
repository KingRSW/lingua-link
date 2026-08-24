#!/usr/bin/env bash
#
# publish_release.sh — 把 dist/ 产物一键发到 GitHub Release
# ----------------------------------------------------------------------------
# 前置: 仓库已 push；macOS 钥匙串里存有 github.com 的凭据（Personal Access Token）。
# 用法:
#   ./publish_release.sh            # 默认 TAG=vX.Y.Z（读 pubspec version）
#   TAG=v1.0.0 ./publish_release.sh # 指定 tag
#   REPO=owner/repo ./publish_release.sh
#
# 行为:
#   1. 从钥匙串取 github token
#   2. 若 Release(tag) 不存在则创建；存在则复用并删掉同名旧 asset
#   3. 上传 dist/ 下: *.ipa / *android*.apk / *.dmg（文件名 translate_app-* 规整为 lingua-link-*）
# ----------------------------------------------------------------------------
set -uo pipefail

REPO="${REPO:-KingRSW/lingua-link}"
DIST="${DIST:-dist}"
PV="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
VER="${PV%%+*}"
TAG="${TAG:-v${VER}}"

export GH_TOKEN="$(printf 'protocol=https\nhost=github.com\n' | git credential-osxkeychain get 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$GH_TOKEN" ] || { echo "[XX] 无法从钥匙串取得 github token"; exit 1; }

python3 - "$REPO" "$DIST" "$TAG" "$VER" <<'PYEOF'
import sys, os, json, glob
import urllib.request, urllib.error, urllib.parse

repo, dist, tag, ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
token = os.environ["GH_TOKEN"]
api = f"https://api.github.com/repos/{repo}"
hdr = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "Content-Type": "application/json"}

body = f"""# Lingua Link 翻译 v{ver}

## 下载
- **iOS**: `lingua-link-{ver}-ios.ipa` —— 未签名包，需用你自己的 Apple ID 在爱思助手(3uTools) 侧载重签（仓库根目录 sign.sh / resign_iphone.sh 可用）。免费 Apple ID 签名有效期 7 天。
- **Android**: `lingua-link-{ver}-android-arm64.apk`（绝大多数手机）／armeabi／x86_64 —— 直接安装即可。
- **macOS**: `lingua-link-{ver}-macos.dmg` —— 拖入「应用程序」。未公证，首次打开需在「系统设置→隐私与安全性」点「仍要打开」，或 `sudo xattr -rd com.apple.quarantine /Applications/translate_app.app`。

## 说明
- 后端（会员 / 微信支付回调 / OCR）部署在 Supabase Edge Function；OCR 走智谱视觉模型 glm-4v-flash。
- 源码与各平台构建脚本见仓库 package.sh / package.ps1。
"""

def req(method, url, data=None):
    r = urllib.request.Request(url, data=data, method=method, headers=hdr)
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.read().decode(), resp.status
    except urllib.error.HTTPError as e:
        return e.read().decode(), e.code

# 校验 token
_, code = req("GET", "https://api.github.com/user")
if code != 200:
    print("[XX] token 无效"); sys.exit(1)

# 创建 Release（已存在则获取）
payload = json.dumps({"tag_name": tag, "name": f"Lingua Link v{ver}", "body": body,
                      "draft": False, "prerelease": False}).encode()
out, code = req("POST", f"{api}/releases", payload)
if code not in (200, 201):
    out, code = req("GET", f"{api}/releases/tags/{tag}")
    if code != 200:
        print("[XX] 创建/获取 Release 失败:", code, out[:300]); sys.exit(1)
rel = json.loads(out)
upload_url = rel["upload_url"].split("{")[0]
rel_id = rel["id"]
print("[OK] Release ready:", rel.get("html_url"))

existing = {a["name"]: a["id"] for a in rel.get("assets", [])}

ctypes = {".ipa": "application/octet-stream",
          ".apk": "application/vnd.android.package-archive",
          ".dmg": "application/x-apple-diskimage"}
patterns = ["*.ipa", "*android*.apk", "*.dmg"]
files = []
for pat in patterns:
    files += glob.glob(os.path.join(dist, pat))

uploaded = 0
for f in files:
    if not os.path.isfile(f):
        continue
    name = os.path.basename(f).replace("translate_app-", "lingua-link-")
    ext = os.path.splitext(f)[1]
    if name in existing:
        req("DELETE", f"{api}/releases/assets/{existing[name]}")
        print("[..] 删除旧 asset:", name)
    with open(f, "rb") as fh:
        data = fh.read()
    r = urllib.request.Request(f"{upload_url}?name={urllib.parse.quote(name)}", data=data,
                               method="POST",
                               headers={**hdr, "Content-Type": ctypes.get(ext, "application/octet-stream")})
    try:
        with urllib.request.urlopen(r) as resp:
            print(f"[OK] 已上传 {name} ({len(data)//1024} KB) {resp.status}")
            uploaded += 1
    except urllib.error.HTTPError as e:
        print("[XX] 上传失败", name, e.code, e.read().decode()[:200])

print(f"[OK] 完成：{uploaded} 个产物已上传 -> {rel.get('html_url')}")
PYEOF
