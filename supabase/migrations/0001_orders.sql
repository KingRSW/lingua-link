-- LinguaLink 订单表（Supabase Edge Function 用）
-- 取代原 Cloudflare KV 的 orders 命名空间；PostgREST 读写。
create table if not exists public.orders (
  order_id   text primary key,
  status     text not null default 'pending',
  mode       text not null default 'personal',   -- personal | real
  created_at bigint not null,                     -- 毫秒时间戳
  paid_at    bigint,                              -- 毫秒时间戳，未支付为 null
  payload    jsonb not null default '{}'::jsonb   -- 完整订单对象（与旧 KV 结构一致）
);

create index if not exists idx_orders_status_mode
  on public.orders (status, mode);

-- 仅服务角色（Edge Function）可读写；开启 RLS 并默认拒绝匿名直接访问。
alter table public.orders enable row level security;
