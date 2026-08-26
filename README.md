# 瞬译 · lingua link

> 翻得快，更翻得地道。

一句话翻译，AI 帮你润色到母语级——这是「瞬译」和其他翻译工具最大的不同。

## 📣 标语 / Slogans

（可直接用作 GitHub 仓库简介或落地页文案）

- 瞬译：翻得快，更翻得地道。
- 一句话翻译，AI 帮你润色到母语级。
- 不只是翻译，更懂你怎么说。
- 翻译 + AI 润色，一句说出地道外文。
- 长文秒译，AI 润色，纯净无广告。
- 你负责说，地道交给 AI。
- 让每一句外文，都像本地人说的话。
- lingua link：translation that sounds native.

## ✨ 功能

- **长文本翻译**：单次可译 5000 字（免费版 500 字）
- **AI 润色（PRO）**：地道 / 商务 / 学术 / 简洁 四种语气一键润色
- **翻译历史**：自动保存最近 50 条
- **云端同步**：多设备共享翻译记录
- **无广告** · 高峰期**优先通道**

## 💎 会员

**年费会员 ¥10 / 年** — 微信 / 支付宝安全支付，随时可取消。

## 🔐 卖家确认付款

个人收款码模式下，买家付款后需要卖家在 App 的「卖家确认」页面确认订单，会员才会开通。

- 首次进入「卖家确认」时，输入 Supabase 项目 Secrets 中的 `CONFIRM_SECRET`
- 密钥只保存在卖家自己的设备上，不会写进公开页面或用户端代码
- 点「刷新」查看待确认订单，核对实际到账金额后再点「确认」
- **不要把真实密钥提交到 GitHub、截图或公开文档**

### 显示“密钥错误”怎么办

1. 确认输入的是 Supabase 项目 Secrets 的 `CONFIRM_SECRET`，不是 `SUPABASE_ANON_KEY`、项目 ID 或数据库密码
2. 当前生产项目的密钥以本机 `supabase/CONFIRM_SECRET.txt` 为准；不要把密钥值复制到 README
3. 卖家确认页面会把密钥保存在本机。如果之前保存过旧密钥，需要清除 App 数据后重新输入：卸载 App，再重新安装当前正式版
4. 重新进入「卖家确认」，输入正确密钥并点「保存密钥」
5. 若仍然报错，检查手机网络，并确认 Supabase Edge Function 已部署且项目 Secrets 中存在 `CONFIRM_SECRET`

确认接口使用的请求头是 `x-confirm-secret`，只允许卖家使用；买家不需要填写或接触该密钥。

## 🛠 技术

- Flutter 3 · Dart
- 网页版部署于 **GitHub Pages**
- 支付后端：Cloudflare Workers（微信 v2 / 支付宝 RSA2 真实签名）
- 真实收款「上线清单」见 [`PAYMENT_GO_LIVE.md`](PAYMENT_GO_LIVE.md)
- 亮点与分发策略见 [`MARKETING_SEO.md`](MARKETING_SEO.md)

## 🚀 本地运行 / 部署

- 安装与本地预览：见 `INSTALL_INSTRUCTIONS.md`
- 部署到 GitHub Pages：见 `DEPLOY_GITHUB_PAGES.md`
- 支付后端部署（Cloudflare Workers）：见 `wrangler.toml` 与 `PAYMENT_GO_LIVE.md`
