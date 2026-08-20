/**
 * LinguaLink 会员支付后端（Cloudflare Workers）
 * ---------------------------------------------------------------
 * 部署：wrangler deploy（需先 `npm i -g wrangler` 并登录）
 *
 * 两种运行模式：
 *   ┌──────────┬──────────────────────────────────────────────────────┐
 *   │ DEV      │ 下单返回内置模拟收银台，点「模拟支付成功」即可走完流程。 │
 *   │ (默认)   │ 不接真实微信/支付宝，方便先验证前端交互。              │
 *   ├──────────┼──────────────────────────────────────────────────────┤
 *   │ REAL     │ 调真实微信支付 v2 / 支付宝电脑网站支付，密钥只在后端。 │
 *   │          │ 触发条件：配置了商户号 env 且 PAYMENT_DEV !== 'true'。 │
 *   └──────────┴──────────────────────────────────────────────────────┘
 *
 * ⚠️ 真实模式代码为「骨架」，写入时已按微信 v2 / 支付宝 RSA2 的公开规范实现签名，
 *    但未经你的真实商户号联调。拿到商户号、填好 wrangler secret 后，务必用沙箱/
 *    小额订单实测每一笔支付与回调验签，再对客开放。
 *
 * 生产注意：
 *   - 订单状态用内存 Map 保存，Worker 冷启动会清空。正式上线请改用 KV / D1。
 *   - 异步通知务必校验签名且核对金额，否则会被伪造「支付成功」。
 */

// 套餐价格（与前端 lib/payment/models.dart 对齐；正式以商户平台配置为准）
const PLANS = {
  monthly: { label: '按月会员', priceCny: 9.0, days: 30 },
  yearly: { label: '按年会员', priceCny: 68.0, days: 365 },
  lifetime: { label: '永久会员', priceCny: 198.0, days: null },
};

// 内存订单表（生产请替换为 KV / D1）
const orders = new Map();

// ============================================================
// 工具：编码 / 签名
// ============================================================
function bytesToHex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function randStr(n = 16) {
  const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let s = '';
  for (let i = 0; i < n; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
}
function nonce() {
  return randStr(32);
}

// HMAC-SHA256（微信支付 v2 的 sign_type=HMAC-SHA256 用）
async function hmacSha256Hex(message, key) {
  const keyBuf = new TextEncoder().encode(key);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBuf, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message));
  return bytesToHex(sig).toUpperCase();
}

// RSA2 签名（支付宝用，私钥为 PKCS#8 PEM）
async function rsa2Sign(message, pkcs8Pem) {
  const pem = pkcs8Pem.replace(/-----\w+ PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

// 微信 v2 签名串：参数按 key 升序，非空，key=value&... 再拼 &key=API_KEY
async function wxSign(params, apiKey) {
  const keys = Object.keys(params).filter((k) => k !== 'sign' && params[k] !== '' && params[k] != null)
    .sort();
  const raw = keys.map((k) => `${k}=${params[k]}`).join('&') + `&key=${apiKey}`;
  return hmacSha256Hex(raw, apiKey);
}

// 把对象拼成支付宝签名串（排除 sign/空值，按 key 升序，k=v&...）
function aliSignContent(params) {
  return Object.keys(params)
    .filter((k) => k !== 'sign' && params[k] !== '' && params[k] != null)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
}

// 跨域头（前端 Pages 站点跨域调用本 worker 需要）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
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

// ============================================================
// 真实模式：微信支付 v2 统一下单
// ============================================================
async function wxUnifiedOrder(orderId, plan, env, clientIp) {
  const params = {
    appid: env.WX_APP_ID,
    mch_id: env.WX_MCH_ID,
    nonce_str: nonce(),
    body: `LinguaLink-${plan.label}`,
    out_trade_no: orderId,
    total_fee: Math.round(plan.priceCny * 100), // 单位：分
    spbill_create_ip: clientIp,
    notify_url: env.WX_NOTIFY_URL,
    trade_type: 'NATIVE', // NATIVE=扫码；H5 站点用 'MWEB'
    sign_type: 'HMAC-SHA256',
  };
  params.sign = await wxSign(params, env.WX_API_KEY);
  const xml = `<xml>${Object.keys(params).map((k) => `<${k}>${params[k]}</${k}>`).join('')}</xml>`;
  const resp = await fetch('https://api.mch.weixin.qq.com/pay/unifiedorder', {
    method: 'POST',
    headers: { 'content-type': 'text/xml' },
    body: xml,
  });
  const txt = await resp.text();
  // TODO(联调): 解析 <return_code>/<result_code>/<code_url>，失败要打日志。
  const codeUrl = (txt.match(/<code_url>(?:<!\[CDATA\[)?([^<]+)/) || [])[1];
  return { codeUrl };
}

// ============================================================
// 真实模式：支付宝 电脑网站支付（自动提交表单）
// ============================================================
async function aliPagePay(orderId, plan, env) {
  const bizContent = JSON.stringify({
    out_trade_no: orderId,
    product_code: 'FAST_INSTANT_TRADE_PAY',
    total_amount: plan.priceCny.toFixed(2), // 单位：元
    subject: `LinguaLink-${plan.label}`,
  });
  const params = {
    app_id: env.ALI_APP_ID,
    method: 'alipay.trade.page.pay',
    format: 'JSON',
    charset: 'utf-8',
    sign_type: 'RSA2',
    timestamp: new Date().toISOString().replace(/\.\d+Z$/, '+08:00').slice(0, 19),
    version: '1.0',
    notify_url: env.ALI_NOTIFY_URL,
    return_url: env.ALI_RETURN_URL || '',
    biz_content: bizContent,
  };
  params.sign = await rsa2Sign(aliSignContent(params), env.ALI_PRIVATE_KEY);
  const qs = Object.keys(params).map((k) => `${k}=${encodeURIComponent(params[k])}`).join('&');
  const form = `<!doctype html><html><head><meta charset="utf-8"></head><body>
    <form id="f" action="https://openapi.alipay.com/gateway.do" method="get">
    ${Object.keys(params).map((k) => `<input type="hidden" name="${k}" value="${params[k]}">`).join('')}
    </form><script>document.getElementById('f').submit()</script></body></html>`;
  return { form, qs };
}

// ============================================================
// 1) 下单
// ============================================================
async function createOrder(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const planId = body.plan;
  const channel = body.channel || 'wechat'; // wechat | alipay
  const plan = PLANS[planId];
  if (!plan) return json({ error: 'unknown plan' }, 400);

  const orderId = genOrderId();
  orders.set(orderId, {
    orderId,
    plan: planId,
    channel,
    status: 'pending',
    createdAt: Date.now(),
  });

  const realMode = isRealMode(env);
  if (realMode) {
    try {
      if (channel === 'alipay') {
        const { form, qs } = await aliPagePay(orderId, plan, env);
        orders.get(orderId).payQs = qs;
        return json({ orderId, payUrl: `/pay?orderId=${orderId}&channel=alipay` });
      }
      const clientIp = request.headers.get('CF-Connecting-IP') || '127.0.0.1';
      const { codeUrl } = await wxUnifiedOrder(orderId, plan, env, clientIp);
      return json({ orderId, payUrl: `/pay?orderId=${orderId}&channel=wechat` });
    } catch (e) {
      return json({ error: 'upstream_payment_failed', detail: String(e) }, 502);
    }
  }

  // DEV 模式：内置模拟收银台
  const payUrl = `${new URL(request.url).origin}/pay?orderId=${orderId}`;
  return json({ orderId, payUrl });
}

function isRealMode(env) {
  return env.PAYMENT_DEV !== 'true' && !!env.WX_MCH_ID && !!env.ALI_APP_ID;
}

// ============================================================
// 2) 收银台页（DEV 模拟 / 真实扫码）
// ============================================================
function payPage(orderId, channel, env) {
  const order = orders.get(orderId);
  if (!order) return new Response('订单不存在', { status: 404 });
  const plan = PLANS[order.plan];
  const isReal = isRealMode(env);

  if (isReal && channel === 'wechat') {
    // TODO(联调): 真实模式此处应展示微信返回的 code_url 二维码（可用第三方 QR 库或前端生成）。
    return new Response(`<p>真实微信支付：请展示 code_url 二维码（${order.payQs || ''}）</p>`, {
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  }
  if (isReal && channel === 'alipay') {
    // 支付宝返回的是自动提交表单，直接吐出。
    return new Response(`<p>真实支付宝：应自动跳转收银台（${order.payQs || ''}）</p>`, {
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  }

  // DEV 模拟收银台
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
  function pay(c){ alert('真实模式下将跳转到'+c+'收银台（需配置商户号）'); }
  async function devConfirm(){
    await fetch('/notify',{method:'POST',headers:{'content-type':'application/json'},
      body:JSON.stringify({orderId:'${orderId}'})});
    alert('支付成功！可返回 App 查看会员状态。');
    location.href='/entitlement?orderId=${orderId}&done=1';
  }
  </script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

// ============================================================
// 3) 异步通知（真实为微信/支付宝回调）
// ============================================================
async function notify(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const order = orders.get(body.orderId);
  if (!order) return json({ error: 'unknown order' }, 404);

  if (isRealMode(env)) {
    // TODO(联调): 在此用对应平台的验签逻辑校验回调（微信重算 HMAC-SHA256、
    // 支付宝用 ALI_PUBLIC_KEY 验 RSA2），并核对金额与 out_trade_no，通过才标记 paid。
    // 未实现前不要标记 paid，避免伪造成功。
    return json({ error: 'notify verification not implemented' }, 500);
  }

  // DEV 模式：直接标记（仅本地联调用）
  order.status = 'paid';
  return json({ ok: true });
}

// ============================================================
// 4) 查询权益
// ============================================================
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

// ============================================================
// 5) AI 润色（PRO 权益，接便宜 LLM）
// ============================================================

// OpenAI 兼容聊天补全端点。LLM_BASE_URL 填「拼接 /chat/completions 后正好命中」的基址：
//   DeepSeek: https://api.deepseek.com/v1
//   Zhipu GLM: https://open.bigmodel.cn/api/paas/v4
function llmChatUrl(env) {
  const base = (env.LLM_BASE_URL || 'https://api.deepseek.com/v1').replace(/\/+$/, '');
  return `${base}/chat/completions`;
}

const SCENE_PROMPTS = {
  natural: '把下面这段翻译润色得更地道、自然、符合母语表达习惯，不要改变原意。只输出润色后的文本本身。',
  business: '把下面这段翻译润色得更商务、专业、得体，适合工作沟通。只输出润色后的文本本身。',
  academic: '把下面这段翻译润色得更学术、严谨、书面化。只输出润色后的文本本身。',
  concise: '把下面这段翻译润色得更简洁、明了，去掉冗余。只输出润色后的文本本身。',
};

async function aiPolish(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const text = (body.text || '').toString().slice(0, 4000);
  const scene = SCENE_PROMPTS[body.scene] ? body.scene : 'natural';
  if (!text) return json({ error: 'empty text' }, 400);

  // TODO(生产): 防盗刷/防绕过——AI 润色是付费权益，应在请求带会员 token 并在此处校验
  // （当前权益仅存前端，后端未记录，故先做演示级开放；上线前务必加权益校验+限频）。

  const key = env.LLM_API_KEY;
  if (!key) {
    // DEV 模拟：未配置 LLM 密钥时返回占位，便于前端联调流程。
    return json({ polished: text + '（DEV 模拟润色：配置 LLM_API_KEY 后生效）' });
  }
  try {
    const model = env.LLM_MODEL || 'deepseek-chat';
    const resp = await fetch(llmChatUrl(env), {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: SCENE_PROMPTS[scene] },
          { role: 'user', content: text },
        ],
        temperature: 0.7,
        max_tokens: 2000,
      }),
    });
    const data = await resp.json();
    const content = data?.choices?.[0]?.message?.content?.trim();
    if (!content) return json({ error: 'llm_empty' }, 502);
    return json({ polished: content });
  } catch (e) {
    return json({ error: 'llm_failed', detail: String(e) }, 502);
  }
}

// ============================================================
// 6) 拍照 / 图片 OCR 翻译（PRO 权益，接支持视觉的 LLM）
// ============================================================
function langName(code) {
  if (!code) return '中文';
  const c = code.toLowerCase();
  if (c.startsWith('zh')) return '中文';
  if (c.startsWith('en')) return '英文';
  if (c.startsWith('ja')) return '日文';
  if (c.startsWith('ko')) return '韩文';
  if (c.startsWith('fr')) return '法文';
  if (c.startsWith('de')) return '德文';
  if (c.startsWith('es')) return '西班牙文';
  if (c.startsWith('ru')) return '俄文';
  if (c.startsWith('pt')) return '葡萄牙文';
  if (c.startsWith('it')) return '意大利文';
  return code;
}

// 从 LLM 文本里抠出第一个 JSON 对象（兼容 ```json 代码块包装）。
function extractJson(s) {
  try {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) return JSON.parse(m[0]);
  } catch {
    // ignore
  }
  return null;
}

async function ocr(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const image = body.image;
  const to = (body.to || 'zh-CN').toString();
  if (!image || !image.startsWith('data:')) {
    return json({ error: 'invalid image' }, 400);
  }
  const key = env.LLM_API_KEY;
  if (!key) {
    // DEV 占位：未配置 LLM 密钥时返回提示，便于前端联调流程。
    return json({
      source: '(DEV) 未配置 OCR 后端',
      target: '(DEV) 部署时配置 LLM_API_KEY 即生效（需支持视觉的模型）',
    });
  }
  const langLabel = langName(to);
  const sys = `你是一个 OCR 与翻译助手。请识别图片中的文字，并将其翻译成${langLabel}。`
    + '只输出一个 JSON 对象：{"source": 图片中的原文, "target": 译文}。'
    + '不要输出任何解释或 Markdown 代码块。若图片中无文字，source 与 target 均为空字符串。';
  try {
    const model = env.LLM_MODEL || 'deepseek-chat';
    const resp = await fetch(llmChatUrl(env), {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: sys },
          {
            role: 'user',
            content: [
              { type: 'text', text: '识别并翻译这张图片。' },
              { type: 'image_url', image_url: { url: image } },
            ],
          },
        ],
        temperature: 0.3,
        max_tokens: 2000,
      }),
    });
    const data = await resp.json();
    const content = data?.choices?.[0]?.message?.content?.trim() || '';
    const parsed = extractJson(content);
    return json({
      source: parsed?.source || '',
      target: parsed?.target || content,
    });
  } catch (e) {
    return json({ error: 'ocr_failed', detail: String(e) }, 502);
  }
}

// ============================================================
// 路由入口
// ============================================================
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const p = url.pathname;
    const channel = url.searchParams.get('channel') || 'wechat';

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (p === '/ai-polish' && request.method === 'POST') return aiPolish(request, env);
    if (p === '/ocr' && request.method === 'POST') return ocr(request, env);
    if (p === '/create-order' && request.method === 'POST') return createOrder(request, env);
    if (p === '/pay' && request.method === 'GET')
      return payPage(url.searchParams.get('orderId'), channel, env);
    if (p === '/notify' && request.method === 'POST') return notify(request, env);
    if (p === '/entitlement' && request.method === 'GET')
      return entitlement(url.searchParams.get('orderId'));

    return new Response('LinguaLink Payment Worker', { status: 200 });
  },
};
