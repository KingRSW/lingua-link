# 会员付费「真收钱」上线清单（路线 A）

> 当前 `worker.js` 已是**真实签名骨架**：DEV 模式（默认）照常跑前端流程；配好商户号 env 后切真实模式。
> 本文件是你从「演示」到「真收款」需要做的现实步骤。标 ⏳ 的必须你本人办理。

---

## 第 1 步 ⏳ 办个体工商户营业执照
- 多数城市「个体工商户」免费或几十元，线上（政务服务网/微信小程序）即可申请，约 0.5–3 天。
- 拿到营业执照后才有资格申请微信支付 / 支付宝商户号。

## 第 2 步 ⏳ 申请商户号（两选一或都开）
- **微信支付商户号**：https://pay.weixin.qq.com → 注册 → 填写个体户信息 → 等待审核（1–3 天）。
  - 记下：`APP_ID`（微信公众平台/开放平台）、`商户号 MCH_ID`、`APIv2 密钥`（商户平台 → API 安全 → 设置 APIv2 密钥，32 位，用于 HMAC-SHA256 签名）。
  - 配置「支付回调地址」为你的 worker 地址 + `/notify`（如 `https://xxx.workers.dev/notify`）。
  - ⚠️ 电脑网站收款一般用 `NATIVE`（扫码）或 `MWEB`（H5）；若要 JSAPI 需绑定公众号，个体户通常先走 NATIVE/MWEB。
- **支付宝商户号**：https://open.alipay.com → 入驻 → 创建「网页&移动应用」→ 开通「电脑网站支付」。
  - 记下：`APP_ID`、应用私钥（**PKCS#8** 格式）、支付宝公钥（用于验签回调）。

## 第 3 步 把密钥注入 worker（不写进代码）
```bash
cd "/Users/kingrsw/lingua link"
wrangler secret put WX_APP_ID
wrangler secret put WX_MCH_ID
wrangler secret put WX_API_KEY
wrangler secret put WX_NOTIFY_URL      # 你的 https://<sub>.workers.dev/notify
wrangler secret put ALI_APP_ID
wrangler secret put ALI_PRIVATE_KEY     # PKCS#8 PEM 全文
wrangler secret put ALI_PUBLIC_KEY      # 支付宝公钥（验签回调用）
wrangler secret put ALI_NOTIFY_URL      # 你的 https://<sub>.workers.dev/notify
wrangler secret put ALI_RETURN_URL      # 可选，支付后跳回页
```

## 第 4 步 部署后端
```bash
wrangler deploy
```
部署成功会得到 `https://<你的子域>.workers.dev`。

## 第 5 步 关 DEV 模式、重部署前端 Pages
```bash
flutter build web --release \
  --dart-define=PAYMENT_DEV=false \
  --dart-define=PAYMENT_BACKEND=https://<你的子域>.workers.dev
# 推上去触发 GitHub Pages 重新部署（见下方）
```
`PAYMENT_DEV=false` 后，`isRealMode()` 因检测到商户号 env 而走真实模式。

## 第 6 步 ⏳ 真实联调（关键，别跳过）
- 用微信/支付宝**沙箱**先跑一遍（微信支付有 sandbox 网关，支付宝有 openapi.alipaydev.com）。
- 小额真实订单实测：下单 → 拉起收银台 → 支付 → `/notify` 收到回调 → `/entitlement` 返回 `isPremium:true`。
- 重点核对：`worker.js` 的 `notify()` 真实验签逻辑（微信重算 HMAC-SHA256、支付宝用 `ALI_PUBLIC_KEY` 验 RSA2）**目前是 TODO**，上线前必须补全并验证，否则会被伪造「支付成功」。
- 金额一致性：回调里的金额必须与订单金额（分 / 元）一致。

## 第 7 步 合规
- 微信/支付宝商户入驻与 App 上架都要求《隐私政策》，补一个页面并在 paywall/关于里挂链接。
- iOS 若以后上架，苹果 3.1.1 禁止用微信/支付宝内购，必须走 Apple IAP（$99/年）。

---

## 当前代码里还差的 TODO（上线前补）
- `worker.js` `notify()`：真实模式验签 + 金额核对（现在是 500 占位）。
- `worker.js` 微信真实收银台：把 `code_url` 渲染成二维码（可引一个 QR 库或前端生成）。
- 订单持久化：内存 Map 改 KV / D1（否则 Worker 重启丢订单）。
- `wrangler.toml`：把上面 secret 对应的 `[vars]`/`[[kv_namespaces]]` 注释打开。
