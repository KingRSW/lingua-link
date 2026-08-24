# 手机全自动确认（个人收款码模式）

闭环：用户付款 → 你手机收到微信/支付宝到账通知 → 手机自动调 `/confirm-paid` → 用户端每 2 秒轮询 `entitlement` 检测到 `paid` → 自动开通会员（用户无需输码、无需等你手动跑脚本）。

---

## 第 0 步：让后端对手机可达（必须）

上次会话结束，本地服务（wrangler / 静态服务 / cloudflared）都已停。手机要能访问后端，二选一：

- **方案 A（稳定，推荐正式用）**：`wrangler deploy` 部署到 Cloudflare，拿到固定 `https://lingua-link.<你的子域>.workers.dev`。需要 Cloudflare 登录 + 邮箱验证一次。
- **方案 B（临时测试）**：重启 cloudflared 隧道拿 `https://xxxx.trycloudflare.com`（重启会变、会话结束会断）。

拿到后端的 BASE URL（下文记作 `<BACKEND_URL>`），手机自动化里就用它。

---

## 第 1 步：拿到确认密钥

密钥在仓库根 `.dev.vars` 的 `CONFIRM_SECRET`（当前 dev 值：`lingua-dev-confirm-2026`）。
这是**只你持有**的密钥，绝不下发前端，用户拿不到 → 无法自己调接口白嫖开通。手机自动化里原样粘贴这个值。

---

## 接口契约（手机请求长这样）

```
POST <BACKEND_URL>/confirm-paid
Headers:
  content-type: application/json
  x-confirm-secret: <你的CONFIRM_SECRET>
Body (JSON 二选一):
  { "amountCny": 68 }        # 按金额自动匹配最近一笔待付订单（手机用这个）
  { "orderId": "LL-xxxx" }   # 按订单号精确确认（最稳，但手机难拿到订单号）
```

---

## 套餐金额（amountCny 取值）

| 套餐 | 价格 | amountCny |
|------|------|-----------|
| 按月会员 | ¥9.00 | `9` |
| 按年会员 | ¥68.00 | `68` |
| 永久会员 | ¥198.00 | `198` |

三档金额互不相同，所以 `findPendingByAmount` 能靠金额准确命中对应订单。

---

## iOS 快捷指令（按套餐建自动化，免解析通知）

> iOS 限制：个人自动化「收到通知」**拿不到通知正文的文字**，所以无法直接解析出金额。
>  workaround：每个套餐用「固定金额」建一个自动化，后端按金额匹配最近待付订单即可。
> 若你只卖一个套餐，只要 2 个自动化（微信 + 支付宝）就够。

以「微信 + 按年 ¥68」为例：

1. 打开 **快捷指令** → **自动化** → 右上角 **+** → **创建个人自动化** → **当收到通知**。
2. App 选 **微信**；点「信息包含」可加过滤 `收款` 或 `支付`（减少误触发）。
3. 添加操作 → 搜索 **获取 URL 的内容**：
   - **URL**：`<BACKEND_URL>/confirm-paid`
   - **方法**：`POST`
   - **头部**：点 `+` 添加 `x-confirm-secret` = `<你的CONFIRM_SECRET>`
   - **请求体**：打开 → 格式选 **JSON** → 字段 `amountCny` = `68`（填数字，别带引号）
4. **关闭「运行前询问」**（iOS 16+ 在自动化编辑页底部开关）→ 后台静默自动跑，不用你点。
5. **复制**这个自动化：改 App=支付宝、或改 `amountCny`=9 / 198，覆盖 3 套餐 × 2 App。

测试：手动跑一次该快捷指令，应返回 `{"ok":true,...}`。

---

## Android（Tasker，动态解析金额，真·全自动多套餐，推荐）

Android 能读通知正文，所以一份配置搞定全部套餐：

1. 装 **Tasker**；设置里给 **通知访问 / 通知监听** 权限。
2. **配置文件** → 事件 → UI → **通知** → 所有者应用：`微信`、`支付宝`（可建两个或一个含多应用）。
3. **任务** → **HTTP 请求**：
   - 方法：`POST`
   - URL：`<BACKEND_URL>/confirm-paid`
   - 头部：`x-confirm-secret:<你的CONFIRM_SECRET>`、`Content-Type:application/json`
   - 正文：`{"amountCny":%amt}`（`%amt` 用「变量搜索/正则」从通知文本 `%evtprm()` 提取，正则如 `收款\s*([\d.]+)\s*元?`）
   - **If** 条件：仅当 `%amt` ∈ {9,68,198} 才发（防误触发把无关通知当付款）。
4. 保存并启用。用户付款 → 你真机到账通知 → 自动 POST → 开通。

（嫌 Tasker 贵可用 **MacroDroid**，逻辑相同：通知触发 → 正则取金额 → HTTP POST。）

---

## 安全说明

- `CONFIRM_SECRET` 只在你本机 `.dev.vars` 和你的手机里，用户端只轮询 `entitlement`，拿不到密钥。
- 服务端金额核对：`confirm-paid` 只会把「待付 + 金额相符」的订单标 `paid`，不会凭空开通；用户伪造金额匹配不到订单就 404。

---

## 端到端验证

1. 用另一台手机（或浏览器无痕）当「付款用户」打开前端链接 → 选套餐 → 扫你的个人收款码付款。
2. 你真机收到微信/支付宝到账通知 → 自动化触发 POST `/confirm-paid`。
3. 用户端每 2 秒轮询，约 2 秒内检测到 `paid` → 弹「✅ 会员已开通」并自动关闭弹窗。

> 备援：自动化万一没触发，你仍可手动 `node tools/confirm_paid.mjs 68`（或订单号）兜底确认。
