-- RouteFlow — ระบบเปิด/ปิดฟีเจอร์ (feature toggle) + คอลัมน์ ออร์เดอร์/COD
-- ฟีเจอร์ทำไว้แต่ "ปิดอยู่" (enabled=false) — Admin เปิดได้ในหน้า ตั้งค่า ของแดชบอร์ด
-- รันครั้งเดียวใน Supabase → SQL Editor

-- 1) ตารางสวิตช์เปิด/ปิดฟีเจอร์ (อ่านได้ทุกคน · เปิด/ปิดได้เฉพาะ admin)
create table if not exists public.app_settings (
  key        text primary key,
  enabled    boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists as_read on public.app_settings;
create policy as_read on public.app_settings for select using (auth.uid() is not null);
drop policy if exists as_write on public.app_settings;
create policy as_write on public.app_settings for all
  using (public.current_role() = 'admin') with check (public.current_role() = 'admin');

-- ฟีเจอร์เริ่มต้น = ปิดทั้งหมด
insert into public.app_settings (key, enabled) values
  ('pod_details', false),   -- แสดงผู้รับ/ลายเซ็น/ตีกลับ ในรายละเอียดทริป (แดชบอร์ด)
  ('orders_cod',  false)    -- ออร์เดอร์/บิล + เก็บเงินปลายทาง (COD) ต่อร้าน
on conflict (key) do nothing;

-- 2) คอลัมน์ ออร์เดอร์/COD ต่อจุดส่ง (ใช้เมื่อเปิดฟีเจอร์ orders_cod)
alter table public.trip_stops add column if not exists cod_amount       numeric;  -- ยอดเก็บเงินปลายทาง (วางแผน)
alter table public.trip_stops add column if not exists collected_amount numeric;  -- เก็บเงินได้จริง (คนขับกรอก)
alter table public.trip_stops add column if not exists order_note       text;     -- รายการสินค้า/เลขบิล

comment on table public.app_settings is 'สวิตช์เปิด/ปิดฟีเจอร์ — แก้ได้เฉพาะ admin';
