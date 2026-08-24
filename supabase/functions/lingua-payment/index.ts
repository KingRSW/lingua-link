/**
 * LinguaLink 会员支付后端（Supabase Edge Function · Deno）
 * ---------------------------------------------------------------
 * 由 Cloudflare Workers 版 worker.js 改写而来：
 *   - 订单存储：KV  →  Postgres（public.orders 表，PostgREST 读写）
 *   - 环境变量：wrangler secret  →  Deno.env.get（supabase secrets set 注入）
 *   - 运行时：Workers  →  Deno（Web Crypto / btoa / atob 均原生支持）
 *
 * Supabase 会自动把 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 注入函数环境，
 * 我们用 service_role 钥匙读写 orders 表（绕过 RLS）。
 *
 * 两种运行模式（与前端 lib/payment/models.dart 对齐）：
 *   PAYMENT_MODE=personal：个人收款码模式（免营业执照），下单返双码+订单号，
 *                          卖家在微信/支付宝看到到账后，用手机快捷指令调
 *                          /confirm-paid 按金额自动确认 → 标 paid → 用户端轮询开通。
 *   PAYMENT_MODE=real   ：真实微信/支付宝商户模式（需配置商户号密钥）。
 *
 * 部署：supabase functions deploy lingua-payment --project-ref <ref>
 * 鉴权：config.toml 设 verify_jwt=false（前端/手机不带 Supabase JWT）。
 */

// ============================================================
// 套餐价格（与前端对齐；正式以商户平台配置为准）
// ============================================================
const PLANS: Record<string, { label: string; priceCny: number; days: number | null }> = {
  monthly: { label: '按月会员', priceCny: 1.0, days: 30 },
  yearly: { label: '按年会员', priceCny: 10.0, days: 365 },
};

// ============================================================
// 环境变量（Deno.env.get）
// ============================================================
// 任意属性访问都落到 Deno.env.get，等价于原 worker 的 env 对象。
const env: Record<string, string | undefined> = new Proxy(
  {},
  { get: (_t, p: string | symbol) => Deno.env.get(String(p)) },
) as Record<string, string | undefined>;

// ============================================================
// PostgREST 数据访问（orders 表）
// ============================================================
const SB_URL = Deno.env.get('SUPABASE_URL') || '';
const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

async function sbReq(method: string, path: string, body?: unknown, extra?: Record<string, string>) {
  const headers: Record<string, string> = {
    apikey: SB_KEY,
    Authorization: `Bearer ${SB_KEY}`,
    'content-type': 'application/json',
    ...(extra || {}),
  };
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return res;
}

async function getOrder(_e: unknown, id: string): Promise<any | null> {
  const res = await sbReq('GET', `orders?order_id=eq.${encodeURIComponent(id)}&select=payload`);
  if (!res.ok) return null;
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length === 0) return null;
  return rows[0].payload;
}

async function putOrder(_e: unknown, order: any): Promise<void> {
  await sbReq(
    'POST',
    'orders?on_conflict=order_id',
    {
      order_id: order.orderId,
      status: order.status || 'pending',
      mode: order.mode || 'personal',
      created_at: order.createdAt,
      paid_at: order.paidAt ?? null,
      payload: order,
    },
    { Prefer: 'resolution=merge-duplicates' },
  );
}

async function markPaid(_e: unknown, orderId: string): Promise<boolean> {
  const order = await getOrder(_e, orderId);
  if (!order) return false;
  order.status = 'paid';
  order.paidAt = Date.now();
  await putOrder(_e, order);
  return true;
}

async function findPendingByAmount(_e: unknown, amountCny: number): Promise<any | null> {
  const res = await sbReq('GET', 'orders?status=eq.pending&mode=eq.personal&select=payload');
  if (!res.ok) return null;
  const rows = await res.json();
  const hit = (Array.isArray(rows) ? rows : [])
    .map((r: any) => r.payload)
    .filter((o: any) => o && o.status === 'pending' && o.mode === 'personal')
    .filter((o: any) => {
      const p = PLANS[o.plan];
      return p && Math.abs((p.priceCny || 0) - amountCny) < 0.01;
    });
  if (hit.length === 0) return null;
  hit.sort((a: any, b: any) => (b.createdAt || 0) - (a.createdAt || 0));
  return hit[0];
}

// ============================================================
// 工具：编码 / 签名
// ============================================================
function bytesToHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function randStr(n = 16): string {
  const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let s = '';
  for (let i = 0; i < n; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
}
function nonce(): string {
  return randStr(32);
}

async function hmacSha256Hex(message: string, key: string): Promise<string> {
  const keyBuf = new TextEncoder().encode(key);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBuf, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message));
  return bytesToHex(sig).toUpperCase();
}

async function rsa2Sign(message: string, pkcs8Pem: string): Promise<string> {
  const pem = pkcs8Pem.replace(/-----\w+ PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

async function wxSign(params: Record<string, any>, apiKey: string): Promise<string> {
  const keys = Object.keys(params)
    .filter((k) => k !== 'sign' && params[k] !== '' && params[k] != null)
    .sort();
  const raw = keys.map((k) => `${k}=${params[k]}`).join('&') + `&key=${apiKey}`;
  return hmacSha256Hex(raw, apiKey);
}

function aliSignContent(params: Record<string, any>): string {
  return Object.keys(params)
    .filter((k) => k !== 'sign' && params[k] !== '' && params[k] != null)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
}

async function rsa2Verify(message: string, signatureB64: string, spkiPem: string): Promise<boolean> {
  const pem = spkiPem.replace(/-----\w+ PUBLIC KEY-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'spki', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
  );
  const sig = Uint8Array.from(atob(signatureB64), (c) => c.charCodeAt(0));
  return crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, new TextEncoder().encode(message));
}

function parseWxXml(xml: string): Record<string, string> {
  const out: Record<string, string> = {};
  const re = /<(\w+)>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([^<]*))<\/\1>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) out[m[1]] = m[2] !== undefined ? m[2] : m[3];
  return out;
}
function wxXmlResp(returnCode: string): string {
  return `<xml><return_code><![CDATA[${returnCode}]]></return_code></xml>`;
}

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-membership-token, x-confirm-secret',
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
  });
}

function genOrderId(): string {
  return 'LL-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
}
function expireAtFor(planId: string): string | null {
  const p = PLANS[planId];
  if (!p || p.days == null) return null;
  return new Date(Date.now() + p.days * 86400 * 1000).toISOString();
}

// ============================================================
// 会员凭证与兑换码
// ============================================================
const DEV_REDEEM_SECRET = 'lingua-dev-redeem-2026';
const DEV_TOKEN_SECRET = 'lingua-dev-token-2026';
const RATE_LIMIT = 30;
const RATE_WINDOW = 60;
const rateBuckets = new Map<string, { window: number; count: number }>();

function b64urlEncode(str: string): string {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlEncodeBytes(buf: ArrayBuffer): string {
  let s = '';
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(str: string): string {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(str);
  return decodeURIComponent(escape(bin));
}
async function hmacSign(message: string, key: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message));
}
function base32(buf: ArrayBuffer): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bytes = new Uint8Array(buf);
  let bits = 0, value = 0, out = '';
  for (let i = 0; i < bytes.length; i++) {
    value = (value << 8) | bytes[i];
    bits += 8;
    while (bits >= 5) {
      out += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += alphabet[(value << (5 - bits)) & 31];
  return out;
}
async function redeemSig(middle: string, secret: string): Promise<string> {
  const sig = await hmacSign('LINGUA-' + middle, secret);
  return base32(sig).slice(0, 6);
}
function tokenTtlSec(): number {
  const d = parseInt(env.TOKEN_TTL_DAYS || '30', 10);
  return (isNaN(d) ? 30 : d) * 86400;
}
async function signToken(sub: string): Promise<string> {
  const secret = env.TOKEN_SECRET || DEV_TOKEN_SECRET;
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { sub, iat: now, exp: now + tokenTtlSec() };
  const h = b64urlEncode(JSON.stringify(header));
  const p = b64urlEncode(JSON.stringify(payload));
  const sig = await hmacSign(`${h}.${p}`, secret);
  return `${h}.${p}.${b64urlEncodeBytes(sig)}`;
}
async function verifyToken(token: string | null): Promise<any | null> {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const secret = env.TOKEN_SECRET || DEV_TOKEN_SECRET;
  const sig = await hmacSign(`${parts[0]}.${parts[1]}`, secret);
  const expect = b64urlEncodeBytes(sig);
  if (expect.length !== parts[2].length) return null;
  let ok = 1;
  for (let i = 0; i < expect.length; i++) {
    ok &= (expect.charCodeAt(i) === parts[2].charCodeAt(i) ? 1 : 0);
  }
  if (!ok) return null;
  try {
    const payload = JSON.parse(b64urlDecode(parts[1]));
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}
function bearerToken(request: Request): string {
  const auth = request.headers.get('authorization') || '';
  if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim();
  return request.headers.get('x-membership-token') || '';
}
function rateLimited(key: string): boolean {
  const now = Math.floor(Date.now() / 1000);
  const b = rateBuckets.get(key);
  if (!b || now - b.window >= RATE_WINDOW) {
    rateBuckets.set(key, { window: now, count: 1 });
    return false;
  }
  b.count += 1;
  return b.count > RATE_LIMIT;
}
async function requireMember(request: Request): Promise<Response | null> {
  const payload = await verifyToken(bearerToken(request));
  if (!payload) {
    return json({ error: 'unauthorized', code: 'no_membership',
      message: '需要有效的会员凭证（请先在 App 内用兑换码解锁）' }, 401);
  }
  if (rateLimited('rate:' + (payload.sub || 'anon'))) {
    return json({ error: 'rate_limited', message: '请求过于频繁，请稍后再试' }, 429);
  }
  return null;
}

async function redeem(request: Request): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const code = ((body.code || '') + '').trim().toUpperCase();
  const parts = code.split('-');
  if (parts.length !== 3 || parts[0] !== 'LINGUA') return json({ error: 'invalid_code' }, 400);
  const middle = parts[1], given = parts[2];
  if (!/^[0-9A-Z]{6}$/.test(middle) || !/^[0-9A-Z]{6}$/.test(given)) {
    return json({ error: 'invalid_code' }, 400);
  }
  const secret = env.REDEEM_SECRET || DEV_REDEEM_SECRET;
  if ((await redeemSig(middle, secret)) !== given) {
    return json({ error: 'invalid_code', message: '兑换码无效或已被伪造' }, 400);
  }
  const token = await signToken(middle);
  return json({
    ok: true,
    token,
    isPremium: true,
    source: 'redeem',
    expireAt: new Date(Date.now() + tokenTtlSec() * 1000).toISOString(),
  });
}

// ============================================================
// 真实模式：微信支付 v2 统一下单
// ============================================================
async function wxUnifiedOrder(orderId: string, plan: any, clientIp: string): Promise<{ codeUrl?: string }> {
  const params: Record<string, any> = {
    appid: env.WX_APP_ID,
    mch_id: env.WX_MCH_ID,
    nonce_str: nonce(),
    body: `LinguaLink-${plan.label}`,
    out_trade_no: orderId,
    total_fee: Math.round(plan.priceCny * 100),
    spbill_create_ip: clientIp,
    notify_url: env.WX_NOTIFY_URL,
    trade_type: 'NATIVE',
    sign_type: 'HMAC-SHA256',
  };
  params.sign = await wxSign(params, env.WX_API_KEY || '');
  const xml = `<xml>${Object.keys(params).map((k) => `<${k}>${params[k]}</${k}>`).join('')}</xml>`;
  const resp = await fetch('https://api.mch.weixin.qq.com/pay/unifiedorder', {
    method: 'POST',
    headers: { 'content-type': 'text/xml' },
    body: xml,
  });
  const txt = await resp.text();
  const codeUrl = (txt.match(/<code_url>(?:<!\[CDATA\[)?([^<]+)/) || [])[1];
  return { codeUrl };
}

async function aliPagePay(orderId: string, plan: any): Promise<{ form: string; qs: string }> {
  const bizContent = JSON.stringify({
    out_trade_no: orderId,
    product_code: 'FAST_INSTANT_TRADE_PAY',
    total_amount: plan.priceCny.toFixed(2),
    subject: `LinguaLink-${plan.label}`,
  });
  const params: Record<string, any> = {
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
  params.sign = await rsa2Sign(aliSignContent(params), env.ALI_PRIVATE_KEY || '');
  const qs = Object.keys(params).map((k) => `${k}=${encodeURIComponent(params[k])}`).join('&');
  const form = `<!doctype html><html><head><meta charset="utf-8"></head><body>
    <form id="f" action="https://openapi.alipay.com/gateway.do" method="get">
    ${Object.keys(params).map((k) => `<input type="hidden" name="${k}" value="${params[k]}">`).join('')}
    </form><script>document.getElementById('f').submit()</script></body></html>`;
  return { form, qs };
}

// ============================================================
// 0.5) 新订单通知（卖家侧，渠道可配置，无需 Apple 付费推送）
// ============================================================
async function notifySeller(order: any): Promise<void> {
  const url = env.SELLER_NOTIFY_URL;
  if (!url) return; // 未配置则静默跳过，不影响下单
  const title = 'LinguaLink 新订单';
  const body = `${order.label} ¥${order.priceCny} 待确认（${order.orderId}）`;
  try {
    if (url.includes('api.day.app')) {
      // Bark: GET https://api.day.app/<key>/<title>/<body>
      await fetch(`${url}/${encodeURIComponent(title)}/${encodeURIComponent(body)}`);
    } else if (url.includes('api.telegram.org')) {
      // Telegram Bot API: <base>?chat_id=...&text=...
      await fetch(`${url}&text=${encodeURIComponent(body)}`);
    } else if (url.includes('pushplus')) {
      // 推送加：POST https://www.pushplus.plus/send {token,title,content}，token 从配置 URL 的 ?token= 取
      const token = new URL(url).searchParams.get('token') || '';
      await fetch('https://www.pushplus.plus/send', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token, title, content: body }),
      });
    } else {
      // 通用 POST JSON（pushplus / 企业微信 / 自建等）
      await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ title, body, orderId: order.orderId, plan: order.plan, priceCny: order.priceCny }),
      });
    }
  } catch (e) {
    console.error('notifySeller failed:', e);
  }
}

// ============================================================
// 1) 下单
// ============================================================
async function createOrder(request: Request): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const planId = body.plan;
  const channel = body.channel || 'wechat';
  const plan = PLANS[planId];
  if (!plan) return json({ error: 'unknown plan' }, 400);

  // 个人收款码模式（免营业执照）
  if ((env.PAYMENT_MODE || 'dev') === 'personal') {
    const orderId = genOrderId();
    const order = { orderId, plan: planId, mode: 'personal', status: 'pending', createdAt: Date.now(), priceCny: plan.priceCny, label: plan.label };
    await putOrder(env, order);
    await notifySeller(order); // 有新订单即推送提醒给卖家
    return json({
      orderId,
      mode: 'personal',
      plan: planId,
      priceCny: plan.priceCny,
      label: plan.label,
      wxQr: env.PERSONAL_WX_QR || '',
      aliQr: env.PERSONAL_ALI_QR || '',
    });
  }

  const orderId = genOrderId();
  const order: any = { orderId, plan: planId, channel, status: 'pending', createdAt: Date.now() };
  await putOrder(env, order);

  const origin = new URL(request.url).origin;

  if (wxConfigured() && channel === 'wechat') {
    try {
      const clientIp = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || '127.0.0.1';
      const { codeUrl } = await wxUnifiedOrder(orderId, plan, clientIp);
      if (!codeUrl) return json({ error: 'wx_no_code_url' }, 502);
      order.codeUrl = codeUrl;
      await putOrder(env, order);
      return json({ orderId, channel: 'wechat', codeUrl });
    } catch (e) {
      return json({ error: 'upstream_payment_failed', detail: String(e) }, 502);
    }
  }
  if (aliConfigured() && channel === 'alipay') {
    try {
      const { form } = await aliPagePay(orderId, plan);
      order.payForm = form;
      await putOrder(env, order);
      return json({ orderId, channel: 'alipay', payUrl: `${origin}/pay?orderId=${orderId}&channel=alipay` });
    } catch (e) {
      return json({ error: 'upstream_payment_failed', detail: String(e) }, 502);
    }
  }
  // DEV 模式：内置模拟收银台
  const payUrl = `${origin}/pay?orderId=${orderId}`;
  return json({ orderId, channel: 'dev', payUrl });
}

function wxConfigured(): boolean {
  return env.PAYMENT_DEV !== 'true' && !!env.WX_APP_ID && !!env.WX_MCH_ID && !!env.WX_API_KEY;
}
function aliConfigured(): boolean {
  return env.PAYMENT_DEV !== 'true' && !!env.ALI_APP_ID && !!env.ALI_PRIVATE_KEY;
}
function isRealMode(): boolean {
  return wxConfigured() || aliConfigured();
}

// ============================================================
// 2) 收银台页（DEV 模拟 / 真实扫码）
// ============================================================
async function payPage(orderId: string | null, channel: string): Promise<Response> {
  if (!orderId) return new Response('缺少 orderId', { status: 400 });
  const order = await getOrder(env, orderId);
  if (!order) return new Response('订单不存在', { status: 404 });
  const plan = PLANS[order.plan];
  if (!plan) return new Response('未知套餐', { status: 404 });
  const isReal = isRealMode();

  if (isReal && channel === 'wechat') {
    const codeUrl = order.codeUrl || '';
    const qr = `https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=${encodeURIComponent(codeUrl)}`;
    const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>微信支付 - LinguaLink</title>
      <style>body{font-family:system-ui;max-width:420px;margin:48px auto;padding:0 20px;text-align:center}
      h1{font-size:20px}.plan{background:#f5f6ff;border:1px solid #e0e3ff;border-radius:12px;padding:16px;margin:16px 0}
      img{width:280px;height:280px}.tip{color:#888;font-size:13px}</style></head>
      <body><h1>微信扫码支付</h1>
      <div class="plan"><b>${plan.label}</b><br>¥${plan.priceCny}（微信扫码，真实扣款）</div>
      ${codeUrl ? `<img src="${qr}" alt="微信支付二维码"><p class="tip">请使用微信「扫一扫」支付，成功后返回 App 自动开通。</p>` : '<p>未获取到 code_url，请重试下单。</p>'}
      </body></html>`;
    return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
  }
  if (isReal && channel === 'alipay') {
    return new Response(order.payForm || '<p>未获取到支付宝表单，请重试下单。</p>', {
      headers: { 'content-type': 'text/html; charset=utf-8' },
    });
  }
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
    await fetch('./notify',{method:'POST',headers:{'content-type':'application/json'},
      body:JSON.stringify({orderId:'${orderId}'})});
    alert('支付成功！可返回 App 查看会员状态。');
    location.href='./entitlement?orderId=${orderId}&done=1';
  }
  </script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

// ============================================================
// 3) 异步通知（真实为微信/支付宝回调）
// ============================================================
async function notify(request: Request): Promise<Response> {
  const ct = (request.headers.get('content-type') || '').toLowerCase();
  if (ct.includes('xml')) return wxNotify(request);
  if (ct.includes('form') || ct.includes('urlencoded')) return aliNotify(request);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const order = await getOrder(env, body.orderId);
  if (!order) return json({ error: 'unknown order' }, 404);
  await markPaid(env, body.orderId);
  return json({ ok: true });
}
async function wxNotify(request: Request): Promise<Response> {
  if (!wxConfigured()) return new Response(wxXmlResp('FAIL'), { headers: { 'content-type': 'text/xml' } });
  const xml = await request.text();
  const p = parseWxXml(xml);
  if ((p.return_code || '') !== 'SUCCESS' || (p.result_code || '') !== 'SUCCESS') {
    return new Response(wxXmlResp('FAIL'), { headers: { 'content-type': 'text/xml' } });
  }
  const signSrc = Object.keys(p).filter((k) => k !== 'sign' && p[k] !== '' && p[k] != null)
    .sort().map((k) => `${k}=${p[k]}`).join('&') + `&key=${env.WX_API_KEY}`;
  const calc = (await hmacSha256Hex(signSrc, env.WX_API_KEY || '')).toUpperCase();
  if (calc !== (p.sign || '').toUpperCase()) {
    return new Response(wxXmlResp('FAIL'), { headers: { 'content-type': 'text/xml' } });
  }
  const order = await getOrder(env, p.out_trade_no);
  if (!order) return new Response(wxXmlResp('FAIL'), { headers: { 'content-type': 'text/xml' } });
  if (parseInt(p.total_fee || '0', 10) !== Math.round((PLANS[order.plan]?.priceCny || 0) * 100)) {
    return new Response(wxXmlResp('FAIL'), { headers: { 'content-type': 'text/xml' } });
  }
  await markPaid(env, p.out_trade_no);
  return new Response(wxXmlResp('SUCCESS'), { headers: { 'content-type': 'text/xml' } });
}
async function aliNotify(request: Request): Promise<Response> {
  if (!aliConfigured()) return new Response('failure');
  const text = await request.text();
  const p: Record<string, string> = Object.fromEntries(new URLSearchParams(text));
  if ((p.trade_status || '') !== 'TRADE_SUCCESS' && (p.trade_status || '') !== 'TRADE_FINISHED') {
    return new Response('failure');
  }
  const signSrc = Object.keys(p).filter((k) => k !== 'sign' && k !== 'sign_type' && p[k] !== '' && p[k] != null)
    .sort().map((k) => `${k}=${p[k]}`).join('&');
  const ok = await rsa2Verify(signSrc, p.sign || '', env.ALI_PUBLIC_KEY || '');
  if (!ok) return new Response('failure');
  if (p.app_id !== env.ALI_APP_ID) return new Response('failure');
  const order = await getOrder(env, p.out_trade_no);
  if (!order) return new Response('failure');
  if ((p.total_amount || '') !== (PLANS[order.plan]?.priceCny || 0).toFixed(2)) return new Response('failure');
  await markPaid(env, p.out_trade_no);
  return new Response('success');
}

// ============================================================
// 4) 确认付款（个人收款码模式，卖家侧）
// ============================================================
async function confirmPaid(request: Request): Promise<Response> {
  if (!env.CONFIRM_SECRET) return json({ error: 'confirm not configured' }, 403);
  const secret = request.headers.get('x-confirm-secret') || '';
  if (secret !== env.CONFIRM_SECRET) return json({ error: 'forbidden' }, 403);
  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const orderId = body && body.orderId;
  const amountCny = body && body.amountCny;
  let order: any;
  let matchedBy = 'orderId';
  if (orderId) {
    order = await getOrder(env, orderId);
  } else if (amountCny != null) {
    order = await findPendingByAmount(env, amountCny);
    matchedBy = 'amount';
  }
  if (!order) return json({ error: 'no matching order' }, 404);
  order.status = 'paid';
  await putOrder(env, order);
  return json({ ok: true, orderId: order.orderId, plan: order.plan, matchedBy });
}

// ============================================================
// 5.5) 卖家面板：列出待确认订单（个人收款码模式，需 CONFIRM_SECRET）
// ============================================================
async function sellerPending(request: Request): Promise<Response> {
  if (!env.CONFIRM_SECRET) return json({ error: 'confirm not configured' }, 403);
  const secret = request.headers.get('x-confirm-secret') || '';
  if (secret !== env.CONFIRM_SECRET) return json({ error: 'forbidden' }, 403);
  const res = await sbReq(
    'GET',
    'orders?status=eq.pending&mode=eq.personal&select=payload&order=created_at.desc',
  );
  if (!res.ok) return json({ error: 'db_error' }, 502);
  const rows = await res.json();
  const list = (Array.isArray(rows) ? rows : [])
    .map((r: any) => r.payload)
    .filter((o: any) => o && o.status === 'pending' && o.mode === 'personal')
    .map((o: any) => ({
      orderId: o.orderId,
      plan: o.plan,
      priceCny: o.priceCny,
      label: o.label,
      createdAt: o.createdAt,
    }));
  return json({ orders: list });
}

async function entitlement(orderId: string | null): Promise<Response> {
  if (!orderId) return json({ isPremium: false }, 400);
  const order = await getOrder(env, orderId);
  if (!order) return json({ isPremium: false }, 404);
  if (order.status !== 'paid') {
    return json({ isPremium: false, source: 'purchase' });
  }
  const token = await signToken('order:' + orderId);
  return json({
    isPremium: true,
    source: 'purchase',
    token,
    expireAt: expireAtFor(order.plan),
  });
}

function privacyPage(): Response {
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>隐私政策 - LinguaLink</title>
    <style>body{font-family:system-ui;max-width:680px;margin:40px auto;padding:0 20px;color:#202536;line-height:1.7}
    h1{font-size:22px}h2{font-size:16px;margin-top:28px}</style></head>
    <body><h1>LinguaLink 隐私政策（摘要）</h1>
    <p>本页说明会员支付相关的数据处理方式。</p>
    <h2>我们收集的信息</h2>
    <ul>
      <li>订单号、所选套餐、支付渠道（微信/支付宝）、订单状态与创建时间——用于开通对应会员权益。</li>
      <li>支付成功后签发一枚会员凭证（JWT），仅含订阅标识与有效期，不含任何个人身份信息。</li>
    </ul>
    <h2>我们不与本服务共享的信息</h2>
    <ul>
      <li>支付本身由微信支付 / 支付宝完成，你的银行卡号、支付密码、实名信息均由对应支付机构处理，本服务无法获取。</li>
    </ul>
    <h2>数据留存</h2>
    <ul>
      <li>订单记录用于会员有效期核验，按订阅周期留存；你可随时在 App 内查看会员状态。</li>
    </ul>
    <h2>联系我们</h2>
    <p>如有疑问，可通过 App 内「联系开发者」渠道反馈。</p>
    </body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

// ============================================================
// 5) AI 润色（PRO 权益，接便宜 LLM）
// ============================================================
function llmChatUrl(): string {
  const base = (env.LLM_BASE_URL || 'https://api.deepseek.com/v1').replace(/\/+$/, '');
  return `${base}/chat/completions`;
}
// OCR 视觉模型端点：默认智谱开放平台（glm-4v-flash 免费视觉模型，OpenAI 兼容）。
// 与文本润色（DeepSeek）分离，避免把视觉模型错打到 DeepSeek 端点导致静默失败。
function visionUrl(): string {
  const base = (env.LLM_VISION_BASE_URL || 'https://open.bigmodel.cn/api/paas/v4').replace(/\/+$/, '');
  return `${base}/chat/completions`;
}
const SCENE_PROMPTS: Record<string, string> = {
  natural: '把下面这段翻译润色得更地道、自然、符合母语表达习惯，不要改变原意。只输出润色后的文本本身。',
  business: '把下面这段翻译润色得更商务、专业、得体，适合工作沟通。只输出润色后的文本本身。',
  academic: '把下面这段翻译润色得更学术、严谨、书面化。只输出润色后的文本本身。',
  concise: '把下面这段翻译润色得更简洁、明了，去掉冗余。只输出润色后的文本本身。',
};
async function aiPolish(request: Request): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const text = (body.text || '').toString().slice(0, 4000);
  const scene = SCENE_PROMPTS[body.scene] ? body.scene : 'natural';
  if (!text) return json({ error: 'empty text' }, 400);

  const key = env.LLM_API_KEY;
  if (!key) {
    return json({ polished: text + '（DEV 模拟润色：配置 LLM_API_KEY 后生效）' });
  }
  try {
    const model = env.LLM_MODEL || 'deepseek-chat';
    const resp = await fetch(llmChatUrl(), {
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
// 6) 拍照 / 图片 OCR 翻译（PRO 权益）
// ============================================================
function langName(code: string): string {
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
function extractJson(s: string): any | null {
  try {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) return JSON.parse(m[0]);
  } catch { /* ignore */ }
  return null;
}
async function ocr(request: Request): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400); }
  const image = body.image;
  const to = (body.to || 'zh-CN').toString();
  if (!image || !image.startsWith('data:')) {
    return json({ error: 'invalid image' }, 400);
  }
  // OCR 视觉模型：优先用独立的视觉 key/base，缺省时回退到文本 LLM 的 key（仍走视觉端点）。
  const key = env.LLM_VISION_API_KEY || env.LLM_API_KEY;
  if (!key) {
    return json({
      source: '(DEV) 未配置 OCR 后端',
      target: '(DEV) 部署时配置 LLM_VISION_API_KEY（智谱 glm-4v-flash 免费）即生效',
    });
  }
  const langLabel = langName(to);
  const sys = `你是一个 OCR 与翻译助手。请识别图片中的文字，并将其翻译成${langLabel}。`
    + '只输出一个 JSON 对象：{"source": 图片中的原文, "target": 译文}。'
    + '不要输出任何解释或 Markdown 代码块。若图片中无文字，source 与 target 均为空字符串。';
  try {
    const model = env.LLM_VISION_MODEL || 'glm-4v-flash';
    const resp = await fetch(visionUrl(), {
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
        max_tokens: 1024,
      }),
    });
    if (!resp.ok) {
      const errText = await resp.text();
      return json({ error: 'ocr_upstream', status: resp.status, detail: errText.slice(0, 300) }, 502);
    }
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
Deno.serve(async (request: Request) => {
  const url = new URL(request.url);
  // Supabase 调用 URL 形如 https://<ref>.supabase.co/functions/v1/<slug>/<route>
  // 运行时 pathname 实际为 /<slug>/<route>（/functions/v1 已被网关剥离），
  // 需去掉 slug 前缀才能让路由匹配。下面兼容 /functions/v1/<slug> 与 /<slug> 两种形态。
  let p = url.pathname.replace(/^\/functions\/v1\//, '');
  const segs = p.split('/').filter(Boolean);
  if (segs.length >= 2) p = '/' + segs.slice(1).join('/');
  if (p === '') p = '/';
  const channel = url.searchParams.get('channel') || 'wechat';

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (p === '/ai-polish' && request.method === 'POST') {
    const denied = await requireMember(request);
    if (denied) return denied;
    return aiPolish(request);
  }
  if (p === '/ocr' && request.method === 'POST') {
    const denied = await requireMember(request);
    if (denied) return denied;
    return ocr(request);
  }
  if (p === '/redeem' && request.method === 'POST') return redeem(request);
  if (p === '/create-order' && request.method === 'POST') return createOrder(request);
  if (p === '/pay' && request.method === 'GET') return payPage(url.searchParams.get('orderId'), channel);
  if (p === '/notify' && request.method === 'POST') return notify(request);
  if (p === '/entitlement' && request.method === 'GET') return entitlement(url.searchParams.get('orderId'));
  if (p === '/confirm-paid' && request.method === 'POST') return confirmPaid(request);
  if (p === '/seller-pending' && request.method === 'GET') return sellerPending(request);
  if (p === '/privacy') return privacyPage();

  return new Response('LinguaLink Payment Edge Function', { status: 200 });
});
