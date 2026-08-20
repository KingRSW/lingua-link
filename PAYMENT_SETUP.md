# LinguaLink 会员付费接入指南（微信 / 支付宝，网页版）

> 适用路线：**网页 / PWA + 微信支付 + 支付宝**，前期近 0 元（免费办个体工商户 + 免费 Cloudflare Workers 后端），仅每笔约 0.6% 手续费（从营收出）。
> 方向背景：用户希望像迅雷 / 夸克那样「直接付钱开通会员，不用兑换码」。因「不想花钱」已排除 Apple IAP（$99/年开发者账号），故采用网页版接国内支付的零前期方案。

---

## 现状（已搭好的代码骨架）

| 文件 | 作用 |
| --- | --- |
| `lib/payment/models.dart` | 会员套餐 `Plan`、订单 `Order`、权益 `Entitlement` 数据模型（前后端字段对齐） |
| `lib/payment/payment_provider.dart` | `PaymentProvider` 抽象 + `WechatAlipayProvider` 实现：下单 → 拉起收银台 → 轮询权益。含 **DEV 模式** |
| `lib/subscription_service.dart` | 前端唯一的会员状态入口。`redeemCode` 改为请求后端 `/redeem`（服务端用 `REDEEM_SECRET` 校验签名并签发 membership token），新增 `activatePurchase(Entitlement)`（付费权益） |
| `lib/paywall.dart` | 付费墙 UI：三套餐卡片 + 微信/支付宝按钮 + 兑换码输入区 |
| `worker.js` | Cloudflare Workers 后端：下单 / 模拟收银台 / 异步通知 / 权益查询；新增 `/redeem`（兑换码校验+签 token）与 `/ai-polish`、`/ocr` 的会员 token 门槛 + 限频 |

代码现已能**整链跑通 UI 流程**（DEV 模式，不真实扣款）。要真收钱，按下面补齐账号与配置即可。

---

## 一、免费办个体工商户（约 0 元）

微信支付 / 支付宝商户号**都需要营业执照**，个人开不了。最快路径：

1. 当地「政务服务网 / 市场监管局」线上申请**个体工商户**（经营范围含「信息技术服务 / 软件销售」类即可）。多数地区免费、当天或数日出照。
2. 拿到营业执照 + 经营者身份证，即可申请下方商户号。

> 备选：若暂时不想办执照，可先用「兑换码」灰度（服务端 `/redeem` 校验，已防伪造）；但**真收钱必须经过商户号**。

## 二、申请支付商户号

- **微信支付**：https://pay.weixin.qq.com → 注册商户号（需营业执照、对公/经营者银行卡）。记下 `商户号(mch_id)`、`APIv3 密钥`、`API 证书`。
- **支付宝**：https://open.alipay.com → 创建「网页 & 移动应用」或「当面付」，签约「电脑网站支付 / 手机网站支付」。记下 `app_id`、`应用私钥`、`支付宝公钥`。

## 三、部署后端 `worker.js`

```bash
npm i -g wrangler
wrangler login
cd "lingua link"
wrangler init -y          # 首次：生成 wrangler.toml，把 worker.js 设为 main
wrangler deploy
# 部署后得到 https://lingua-pay.<你的子域>.workers.dev
```

在 `worker.js` 的 `createOrder` / `notify` 里把 TODO 替换为真实统一下单与签名验签（密钥只在后端，前端永不接触）。生产请把内存 `orders` 改为 **Workers KV / D1**，避免冷启动清空。

## 四、前端关掉 DEV 模式并填后端地址

```bash
flutter build web \
  --dart-define=PAYMENT_DEV=false \
  --dart-define=PAYMENT_BACKEND=https://lingua-pay.<你的子域>.workers.dev
```

- `PAYMENT_DEV=false`：走真实 `createOrder` / `queryEntitlement`。
- `PAYMENT_BACKEND`：第三步拿到的 Workers 地址（不要写死在代码里）。

然后照常部署到 GitHub Pages（本项目是 Flutter Web / PWA）。

## 五、本地联调（不花钱先验证流程）

保持默认（DEV 开）直接 `flutter run -d chrome`：点套餐 → 跳到模拟收银台 → 点「模拟支付成功」→ 返回 App 即显示已解锁 PRO。这样能在无商户号时把交互全部跑通。

---

## 合规提醒（重要）

- **网页 / 安卓**：可直接接微信 / 支付宝，符合本方案。
- **iOS App（如未来做）**：Apple 审核指南 3.1.1 要求 App 内数字会员**必须用 Apple IAP**，禁用微信 / 支付宝跳转支付，否则拒审。届时需双轨：网页用微信/支付宝、iOS App 用 Apple IAP（或引导到网页版购买）。
- 异步通知（`/notify`）必须校验微信 / 支付宝签名，否则会被伪造「支付成功」。

## 待推送提醒

兑换码校验 bug 修复（`5e61855`）与付费墙 UI 清理（`4c2bcbe`）两个提交仍在本地未上 GitHub。请在本机执行：

```bash
cd "/Users/kingrsw/lingua link" && git push origin main
```

（沙箱环境当前无法直连 github.com，需你本机推送；本次新增的会员付费骨架文件也请一并提交。）
