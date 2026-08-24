# LinguaLink 后端部署到 Supabase

原 Cloudflare Workers 版 `worker.js` 已改写为 Supabase Edge Function（Deno），
订单存储从 KV 改为 Postgres 表 `public.orders`。本地常驻、关电脑也不掉线。

## 已就绪的文件
- `supabase/config.toml` —— 函数配置，`verify_jwt = false`（前端/手机不带 Supabase JWT）。
- `supabase/migrations/0001_orders.sql` —— 建 `orders` 表（幂等）。
- `supabase/functions/lingua-payment/index.ts` —— 改写后的后端，保留全部端点：
  `/create-order` `/confirm-paid` `/entitlement` `/ai-polish` `/ocr` `/redeem` `/notify` `/pay` `/privacy`。
- `deploy_supabase.sh` —— 一键无头部署。

## 一键部署（需要你的凭证）
1. 打开 https://supabase.com/dashboard/account/tokens 生成一个 **Personal Access Token**。
2. 项目地址 `https://<ref>.supabase.co` 里的 `<ref>` 就是 **Project Ref**。
3. 在本机终端（或在 WorkBuddy 里提供这两个值）：
   ```zsh
   cd "/Users/kingrsw/lingua link"
   SUPABASE_ACCESS_TOKEN=你的PAT SUPABASE_PROJECT_REF=你的ref ./deploy_supabase.sh
   ```
   脚本会自动：登录 → 建表 → 建 public 桶 `payqr` 并上传 `web/pay_qr/*.jpg`
   → 从 `.dev.vars` 注入密钥（含两张收款码 URL）→ 部署函数。

## 部署后

### 函数稳定地址（务必带 /v1/ 前缀！）
- ✅ 正确：`https://<ref>.supabase.co/functions/v1/lingua-payment`
- ❌ 错误：`https://<ref>.supabase.co/functions/lingua-payment`（缺 `/v1/` → 网关直接 404）
- 本项目实测地址：`https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment`

> 踩坑记录：Supabase Functions 网关要求 URL 带 `/functions/v1/<slug>`。调用时 `request.url`
> 的 pathname 实际是 `/<slug>/<route>`（`/functions/v1` 已被网关剥离），所以 `index.ts` 里
> 路由匹配前要先去掉 slug 前缀，否则所有路由都命中不到、整体 404/默认响应。

### apikey 头（可选，但建议带）
- 经验证：本项目的函数网关**不强制**要求 `apikey`（不带也能跑到函数），但部分路径/区域可能校验。
- 前端已统一通过 `backendHeaders()` 带上 `apikey: <anon>`（anon key 为公开密钥，可烤进客户端）。
- 若要在前端/快捷指令里带，anon key 在 Supabase 控制台 Settings → API 的 `anon` / `project API key`。

### 重编前端烤入（关闭 DEV 模式）
一键脚本（已建好）：
```zsh
cd "/Users/kingrsw/lingua link"
chmod +x build_web_supabase.sh
./build_web_supabase.sh KingRSW lingua-link
```
等价于手动：
```zsh
flutter build web --release --base-href=/lingua-link/ \
  --dart-define=PAYMENT_BACKEND=https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment \
  --dart-define=PAYMENT_DEV=false
```
> 注：`build_web_supabase.sh` 把构建产物推到 **`gh-pages` 分支**，线上靠「分支部署」生效
> （见下方「让 GitHub Pages 真正生效」）。`.github/workflows/deploy.yml` 是另一套
> Actions 工作流方案，推到 main 才会自动构建发布，但它需要 PAT 带 `workflow` scope，
> 否则 remote 会拒绝 —— 当前线上走的是 gh-pages 分支部署，不依赖它。

### 手机快捷指令（卖家侧确认付款）
3 个「获取 URL 的内容」动作已更新（在 `shortcuts/`）：
- `LinguaLink确认-¥9.shortcut` / `¥68` / `¥198`
- URL 已改为 `https://wqrxitueiqooakzkwenm.supabase.co/functions/v1/lingua-payment/confirm-paid`
- `x-confirm-secret` 头已改为新值（读 `supabase/CONFIRM_SECRET.txt`，当前 `de0b17cf95e41f408ec795952b348a06`）
- 如需在快捷指令里带 `apikey` 头，加一个 `apikey: <anon>` 请求头即可（可选）。

## 安全说明
生产 `CONFIRM_SECRET` 默认生成强随机值（公开部署不能沿用 dev 密钥，否则可白嫖会员）。
若想沿用旧 dev 密钥，部署前设 `SUPABASE_CONFIRM_SECRET=lingua-dev-confirm-2026` 即可（不推荐）。

## 让 GitHub Pages 真正生效（已踩坑，纯 API 可搞定，无需 workflow scope）

线上 `kingrsw.github.io/lingua-link` 要走 Supabase 后端，必须让它服务 `gh-pages` 分支的新构建。

1. **先判断现状**：`GET /repos/{owner}/{repo}/pages` 看 `build_type`。
   - 若是 `workflow`：线上由 Actions 产物提供，光改分支源无效，必须切成「分支部署」。
2. **切成分支部署（需要 PAT 带 `repo` scope，不需要 `workflow`）**：
   ```zsh
   curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"source":{"branch":"gh-pages","path":"/"},"build_type":"legacy"}' \
     https://api.github.com/repos/KingRSW/lingua-link/pages
   ```
   - `build_type` 合法值只有 `legacy` / `workflow`；传 `branch` 会 422。
   - `DELETE /pages` 对本仓库返回 422「not allowed」，所以只能 PUT 改、不能删了重建。
3. **触发发布 + 清 CDN 缓存**：切到 `legacy` 后，一次**真实的 `git push` 到 `gh-pages`**
   才会触发自动构建并刷新边缘节点（只调 `POST /pages/builds` 不一定清得掉缓存）。
   `build_web_supabase.sh` 推完再 `git push -f origin gh-pages` 一次即可。
4. **防 Jekyll 干扰**：在 `gh-pages` 根目录放一个空 `.nojekyll`，否则 GitHub Pages 的
   Jekyll 可能处理/忽略部分文件（`build_web_supabase.sh` 已加）。
5. **怎么确认上线了**：访问 `https://<user>.github.io/<repo>/.nojekyll` 返回 **200**
   即说明新构建已生效（旧构建没有这个文件）。**不要**靠本机拉全量 `main.dart.js` 再 grep
   后端地址来判断——沙箱到 github.io 只有 ~5KB/s，2.8MB 文件会超时截断、误报 0 处。
   权威判断用：`.nojekyll` 200 + `git show origin/gh-pages:main.dart.js | grep -c <后端地址>`。
