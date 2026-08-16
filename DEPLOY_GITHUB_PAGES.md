# Lingua Link 网页版 · GitHub Pages 部署指南

网页版已经构建好（在 `build/web/`），是一个**可安装、可离线**的 PWA。下面三选一即可发布。

---

## 方式一（推荐）：GitHub Actions 自动部署
**你只需要把源码推到 GitHub，剩下的 GitHub 帮你构建+发布。**

1. 在 github.com 新建一个仓库（公开，名字随意，比如 `lingua-link`）。
2. 在本机终端，进入项目目录，初始化并推送：
   ```zsh
   cd "/Users/kingrsw/lingua link"
   git init
   git add -A
   git commit -m "init Lingua Link"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
3. 推送后，GitHub 会自动跑 `.github/workflows/deploy.yml`：构建网页并发布到 `gh-pages`。
4. 进入仓库 **Settings → Pages → Source 选 "GitHub Actions"**，保存。
5. 几分钟后访问：`https://<你的用户名>.github.io/<仓库名>/`

> 注意：工作流用 `main` 分支触发。如果你的默认分支叫 `master`，把工作流和上面命令里的 `main` 改成 `master`。

---

## 方式二：本机一键脚本
如果你更想在本机构建好再推，用工程里的脚本：
```zsh
cd "/Users/kingrsw/lingua link"
chmod +x deploy_gh_pages.sh
./deploy_gh_pages.sh <你的用户名> <仓库名>
```
脚本会重新构建（base-href 自动设为 `/<仓库名>/`）并推送到 `gh-pages` 分支。之后同样去 Settings → Pages 选 gh-pages 分支即可。

---

## 方式三：用户/组织页（更干净的根路径）
若仓库名就是 `<用户名>.github.io`（用户页），网站根路径就是 `/`，部署更简单：
- 用方式一，但工作流里把 `--base-href="/${{ github.event.repository.name }}/"` 改成 `--base-href="/"`；
- 或方式二脚本改手动 `flutter build web --release --base-href="/"` 再推 gh-pages。
访问地址：`https://<用户名>.github.io/`

---

## 部署后怎么"赚钱"（回顾）
GitHub Pages 本身不付你钱，能赚钱的是网页上的这些位子：
- **打赏/赞助**：在网页里放 爱发电 / Patreon / Ko-fi / 微信赞赏码 链接。
- **广告**：接 Google AdSense（需自定义域名 + 流量 + 审核；翻译类易被判定"为广告而生"）。
- **免费养粉 → 付费 App**：网页版免费攒用户，引导去 App Store/Play 的付费版（$99/$25 上架后做内购）。
- **GitHub Sponsors**：别人按月赞助你（需一定人气）。

> 现实预期：刚上线没人气，赚钱≈0。先当免费作品 + 引流，用户量起来再考虑变现。

---

## 本地预览
不想先上 GitHub 也想看效果：
```zsh
cd "/Users/kingrsw/lingua link/build/web"
python3 -m http.server 8080
# 浏览器打开 http://localhost:8080
```
- 翻译：全平台可用（已验证 MyMemory 接口支持 CORS）。
- 语音输入：电脑/安卓 Chrome 可用；**iOS Safari 不支持 Web Speech 识别**，iPhone 上只能打字翻译。
- 语音朗读（TTS）：主流浏览器均可用。

---

## 高级功能订阅（GitHub Sponsors · 零成本变现）
网页版已内置「高级功能订阅」：免费版单次限 500 字，高级版 5000 字 + 翻译历史 / 云端同步 / 无广告 / 优先通道。
付费走 **GitHub Sponsors**（开发者免费开通、GitHub 不抽成、按月订阅），解锁用「解锁码」——纯前端校验，无需任何后端，正好跑在免费 GitHub Pages 上。

### 上线前必做
1. 打开 `lib/subscription_service.dart`，把 `sponsorHandle` 改成你的 GitHub 用户名：
   ```dart
   static const String sponsorHandle = '你的GitHub用户名';
   ```
2. 去 github.com → 头像 → **Your Sponsors → Create a Sponsor profile**，设置赞助档位（如 $3/月）。
3. （生产建议）删掉 `PaywallScreen` 里的「（测试）临时解锁」按钮和 `SubscriptionService.toggleDevUnlock()`，避免被随意解锁。

### 给赞助者发卡
本机终端运行（生成 3 个解锁码，每人发一个）：
```zsh
cd "/Users/kingrsw/lingua link"
flutter pub get
dart run tools/gen_code.dart
```
赞助者拿到码后，在网页里点右上角皇冠 → 输入解锁码 → 即解锁高级功能。

### 校验原理（透明说明）
解锁码格式 `LINGUA-XXXXXX-XXXXXX`，末段是前段的校验和，由 `subscription_service.dart` 与 `tools/gen_code.dart` 共用同一算法。
纯前端校验**可被技术用户绕过**，对个人小工具足够；若要「不可绕过」，可加一个 serverless 校验（如 Cloudflare Workers，免费额度足够），把 `redeemCode` 改成请求你的函数即可。

