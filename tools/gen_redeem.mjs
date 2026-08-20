// 发行 LinguaLink 兑换码（与 worker.js 的 redeem 校验同算法）。
//
// 运行（Node 22+，无需安装依赖，使用内置 Web Crypto）：
//   node tools/gen_redeem.mjs <MIDDLE> [SECRET]
//   node tools/gen_redeem.mjs                 # 随机生成一段 MIDDLE
//
// 输出形如：LINGUA-KINGRS-<SIG6>
// 末段 SIG6 = HMAC-SHA256("LINGUA-<MIDDLE>", REDEEM_SECRET) 的 Base32 前 6 位。
// 必须与 worker.js 的 REDEEM_SECRET（.dev.vars 或 wrangler secret）保持一致。
//
// 默认 REDEEM_SECRET 与 worker.js 的 DEV 默认值相同；生产请传你自己的密钥：
//   node tools/gen_redeem.mjs KINGRS "你的-REDEEM_SECRET"

const DEFAULT_SECRET = 'lingua-dev-redeem-2026';

function randMiddle() {
  const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let s = '';
  for (let i = 0; i < 6; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
}

// RFC4648 Base32（与 worker.js base32 一致）
function base32(bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
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

async function hmacSign(message, key) {
  const cryptoKey = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message));
}

async function main() {
  const middle = (process.argv[2] || randMiddle()).toUpperCase();
  const secret = process.argv[3] || DEFAULT_SECRET;
  if (!/^[0-9A-Z]{6}$/.test(middle)) {
    console.error('MIDDLE 必须是 6 位 [0-9A-Z]，例如 KINGRS');
    process.exit(1);
  }
  const sig = await hmacSign('LINGUA-' + middle, secret);
  const sigStr = base32(new Uint8Array(sig)).slice(0, 6);
  console.log(`LINGUA-${middle}-${sigStr}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
