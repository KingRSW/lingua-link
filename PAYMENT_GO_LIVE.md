# 会员付费「真收钱」上线清单（路线 A）

> 当前 `worker.js` 已是**真实签名骨架**：DEV 模式（默认）照常跑前端流程；配好商户号 env 后切真实模式。
> 本文件是你从「演示」到「真收款」需要做的现实步骤。标 ⏳ 的必须你本人办理。

---

## 第 1 步 ⏳ 办个体工商户营业执照（实操）

**为什么是个体户**：App 内做「下单 → 自动收银台 → 回调」式微信/支付宝支付，必须有「商户号」；开商户号必须有营业执照。个人收款码不能嵌进 App 自动收款。个体户是最轻量的持证方式——通常不收费、最快当天拿证。

**准备材料**
- 经营者身份证（原件 + 复印件）
- 经营场所证明：房产证复印件，或租赁合同 + 房东房产证；住宅一般可用，部分城市需「住改商」证明（居委会/物业盖章）
- 字号名称（店名）：格式「行政区划 + 字号 + 行业 + 组织形式」，例如「XX区瞬译翻译服务部」
- 经营范围：建议含「翻译服务」「软件开发」「信息技术咨询服务」（要和你后面开的支付类目匹配）

**申请渠道（任选，线上最省事）**
- **辽宁用户（本项目所在地）**：用「辽事通」APP（辽宁政务服务移动端）或 辽宁省政务服务网，搜「个体工商户设立登记」/「企业开办一网通办」；沈阳、大连等市也有本市政务 APP。辽宁多数区县个体户可全程网办、当场办结。
- 其他省份参考：广东「粤商通」、浙江「浙里办」、江苏「苏服办」等同类小程序/APP，搜「个体工商户设立登记」
- 微信/支付宝 搜「电子营业执照」小程序（领照用，全国通用），或当地市场监管局公众号
- 线下：经营场所所在区/县 市场监管所（工商所）/ 行政审批局 窗口

**办理流程**
1. 核名：系统查重并预核准字号（避免重名被驳回）
2. 填报：《个体工商户注册登记申请书》+ 经营场所、经营范围、资金数额
3. 提交：上传/递交材料，部分城市可全程网办
4. 审核：多数城市 0.5–3 个工作日，不少地方当场出证
5. 领照：纸质营业执照，或微信/支付宝「电子营业执照」小程序直接领电子执照（与纸质同等效力）

**拿照后还要做（为开支付商户号铺路）**
- 刻章：公章/财务章（个体户非强制，但建议；几十~一百多元）
- 银行对公账户：微信/支付宝商户结算需绑定对公账户（部分银行免年费，先问清）
- 税务登记：多证合一，但领照后需税务报到（可线上）；个体户多为小规模纳税人，月销售额 10 万以下免征增值税（政策延续中）

> 不想注册公司也能收钱？早期可走「DEV 模式 + 兑换码」：用户加你微信转账、你手动发兑换码解锁（合规灰色地带，仅适合小规模验证，不能自动回调）。要正规 App 内自动收款，仍绕不开营业执照 + 商户号。

拿到营业执照后，进入第 2 步开微信 / 支付宝商户号。


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
