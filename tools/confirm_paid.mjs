// 个人收款码模式「你确认即开通」：收款方（你）在微信/支付宝看到到账后运行。
//
// 用法：
//   node tools/confirm_paid.mjs <orderId>          # 按订单号确认（最稳）
//   node tools/confirm_paid.mjs <金额>             # 按金额自动匹配最近一笔待付订单，如 node tools/confirm_paid.mjs 68
//   [可选] 第 2 个参数指定后端 URL（默认读 .dev.vars 的 PAYMENT_BACKEND，再回落 127.0.0.1:8787）
//
// 例：
//   node tools/confirm_paid.mjs LL-xxxxx-xxxxx
//   node tools/confirm_paid.mjs 68
//   node tools/confirm_paid.mjs 68 https://subjects-extras-perhaps-portions.trycloudflare.com
//
// 说明：
//   - CONFIRM_SECRET 与 PAYMENT_BACKEND 从项目根 .dev.vars 读取（与 wrangler dev 同源）。
//   - backendUrl 默认 http://127.0.0.1:8787（你本机 wrangler dev）。若 worker 跑在公网隧道，
//     传第二个参数指公网地址即可（确认动作打到同一 worker 实例，用户端轮询 /entitlement 即生效）。
//   - 用户不知道 CONFIRM_SECRET，无法自己调 /confirm-paid 白嫖开通。

import { readFileSync } from 'node:fs';

function readDevVars() {
  try {
    const txt = readFileSync(new URL('../.dev.vars', import.meta.url), 'utf-8');
    const m = {};
    for (const line of txt.split('\n')) {
      const mm = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
      if (mm) m[mm[1]] = mm[2].replace(/^["']|["']$/g, '');
    }
    return m;
  } catch {
    return {};
  }
}

const env = readDevVars();
const arg = process.argv[2];
const backend = process.argv[3] || env.PAYMENT_BACKEND || 'http://127.0.0.1:8787';
const secret = env.CONFIRM_SECRET;

if (!arg) {
  console.error('用法:');
  console.error('  node tools/confirm_paid.mjs <orderId>          # 按订单号确认');
  console.error('  node tools/confirm_paid.mjs <金额>             # 按金额自动匹配最近待付订单，如 node tools/confirm_paid.mjs 68');
  console.error('  [可选] 第2参数指定后端: node tools/confirm_paid.mjs 68 https://<worker>');
  process.exit(1);
}
if (!secret) {
  console.error('缺少 CONFIRM_SECRET，请在项目根 .dev.vars 配置（与 wrangler dev 同源）。');
  process.exit(1);
}

// 参数为纯数字 → 按金额匹配；否则视为订单号。
const body = /^\d+(\.\d+)?$/.test(arg) ? { amountCny: parseFloat(arg) } : { orderId: arg };

try {
  const res = await fetch(`${backend}/confirm-paid`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-confirm-secret': secret },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log(`[${res.status}] ${text}`);
  if (!res.ok) process.exit(1);
  console.log('✅ 已确认收款，用户端将自动开通会员（无需输码）。');
} catch (e) {
  console.error('确认失败：', e.message);
  process.exit(1);
}
