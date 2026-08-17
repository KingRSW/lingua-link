/**
 * LinguaLink 会员支付后端（Cloudflare Workers）
 * ---------------------------------------------------------------
 * 部署：wrangler deploy（需先 `npm i -g wrangler` 并登录）
 *
 * 本文件是「可跑通整套 UI 流程」的骨架：
 *   - DEV 模式：下单后返回一个内置的模拟收银台页，点「模拟支付成功」即可走完，
 *     不接真实微信/支付宝，方便你先把前端交互验证清楚。
 *   - 真实模式：把 createOrder / notify 里的 TODO 替换为微信支付「统一下单」
 *     与支付宝「当面付 / 电脑网站支付」的真实签名逻辑（密钥只在后端，前端永不接触）。
 *
 * 生产注意：
 *   - 订单状态在这里用内存 Map 保存，Worker 冷启动会清空。正式上线请改用
 *     Workers KV 或 D1（见各函数内的注释）。
 *   - 真实异步通知务必校验微信/支付宝的签名，否则会被伪造「支付成功」。
 */

// 套餐价格（与前端 lib/payment/models.dart 对齐；正式以商户平台配置为准）
const PLANS = {
  monthly: { label: '按月会员', priceCny: 6.0, days: 30 },
  yearly: { label: '按年会员', priceCny: 60.0, days: 365 },
  lifetime: { label: '永久会员', priceCny: 198.0, days: null },
};

// 内存订单表（生产请替换为 KV / D1）
const orders = new Map();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function genOrderId() {
  return 'LL-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
}

function expireAtFor(planId) {
  const p = PLANS[planId];
  if (!p || p.days == null) return null;
  return new Date(Date.now() + p.days * 86400 * 1000).toISOString();
}

// ---- 1) 下单 ----
async function createOrder(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const planId = body.plan;
  const plan = PLANS[planId];
  if (!plan) return json({ error: 'unknown plan' }, 400);

  const orderId = genOrderId();
  orders.set(orderId, {
    orderId,
    plan: planId,
    status: 'pending', // pending | paid
    createdAt: Date.now(),
  });

  // TODO(真实模式): 调微信/支付宝统一下单接口，拿到真正的 payUrl（H5 / 网站支付链接）。
  //   const payUrl = await callWechatUnifiedOrder(orderId, plan);
  // 这里先用内置模拟收银台页，方便先验证前端流程。
  const payUrl = `${new URL(request.url).origin}/pay?orderId=${orderId}`;

  return json({ orderId, payUrl });
}

// ---- 2) 模拟收银台页（DEV）----
function payPage(orderId) {
  const order = orders.get(orderId);
  if (!order) {
    return new Response('订单不存在', { status: 404 });
  }
  const plan = PLANS[order.plan];
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>支付 - LinguaLink</title>
  <style>body{font-family:system-ui;max-width:420px;margin:48px auto;padding:0 20px}
  h1{font-size:20px}.plan{background:#f5f6ff;border:1px solid #e0e3ff;border-radius:12px;padding:16px;margin:16px 0}
  button{display:block;width:100%;padding:14px;margin:8px 0;border:0;border-radius:10px;font-size:16px;color:#fff;cursor:pointer}
  .wx{background:#07c160}.ali{background:#1677ff}.dev{background:#888}
  .tip{color:#888;font-size:13px}</style></head>
  <body><h1>开通 LinguaLink 会员</h1>
  <div class="plan"><b>${plan.label}</b><br>¥${plan.priceCny}（DEV 模拟，不真实扣款）</div>
  <button class="wx" onclick="pay('wechat')">微信支付</button>
  <button class="ali" onclick="pay('alipay')">支付宝</button>
  <button class="dev" onclick="devConfirm()">模拟支付成功（DEV）</button>
  <p class="tip">真实模式下，微信/支付宝按钮会跳转到各自收银台；此处仅做流程演示。</p>
  <script>
  function pay(channel){ alert('真实模式下将跳转到'+channel+'收银台（需配置商户号）'); }
  async function devConfirm(){
    await fetch('/notify',{method:'POST',headers:{'content-type':'application/json'},
      body:JSON.stringify({orderId:'${orderId}'})});
    alert('支付成功！可返回 App 查看会员状态。');
    location.href='/entitlement?orderId=${orderId}&done=1';
  }
  </script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

// ---- 3) 异步通知（真实为微信/支付宝回调）----
async function notify(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const order = orders.get(body.orderId);
  if (!order) return json({ error: 'unknown order' }, 404);

  // TODO(真实模式): 在这里校验微信/支付宝回调签名（如微信的签名、支付宝的验签），
  // 验签通过且金额一致才标记 paid，否则返回失败，防止伪造「支付成功」。
  order.status = 'paid';

  return json({ ok: true });
}

// ---- 4) 查询权益 ----
function entitlement(orderId) {
  const order = orders.get(orderId);
  if (!order) return json({ isPremium: false }, 404);
  if (order.status !== 'paid') {
    return json({ isPremium: false, source: 'purchase' });
  }
  return json({
    isPremium: true,
    source: 'purchase',
    expireAt: expireAtFor(order.plan),
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const p = url.pathname;

    if (p === '/create-order' && request.method === 'POST') return createOrder(request);
    if (p === '/pay' && request.method === 'GET') return payPage(url.searchParams.get('orderId'));
    if (p === '/notify' && request.method === 'POST') return notify(request);
    if (p === '/entitlement' && request.method === 'GET') {
      return entitlement(url.searchParams.get('orderId'));
    }

    return new Response('LinguaLink Payment Worker', { status: 200 });
  },
};
