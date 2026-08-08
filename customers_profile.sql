-- =====================================================================
-- RouteFlow — migration: โปรไฟล์ร้านค้า + รูปภาพ + บันทึกการซื้อ/ส่ง
-- รันใน Supabase SQL Editor (Ball รันเอง) — แนะนำรันเป็นก้อน 1→4
-- ปลอดภัยรันซ้ำได้ (idempotent: add column if not exists / on conflict)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) เพิ่ม column โปรไฟล์ในตาราง customers
-- ---------------------------------------------------------------------
alter table public.customers
  add column if not exists name_alt      text,            -- ชื่อสำรอง (ไทย/อังกฤษ)
  add column if not exists landmark       text,            -- จุดสังเกตหาร้าน
  add column if not exists vehicle_access text,            -- รถเข้าถึง: car/pickup/6wheel/bike_only
  add column if not exists access_note    text,            -- หมายเหตุการเข้าถึง (ซอยแคบ ฯลฯ)
  add column if not exists owner_name     text,            -- ชื่อเจ้าของร้าน
  add column if not exists phone2         text,            -- เบอร์สำรอง
  add column if not exists line_id        text,
  add column if not exists store_type     text,            -- โชห่วย/มินิมาร์ท/คาเฟ่/ค้าส่ง
  add column if not exists size_tier      text,            -- เล็ก/กลาง/ใหญ่
  add column if not exists open_time      time,            -- เวลาเปิด
  add column if not exists close_time     time,            -- เวลาปิด
  add column if not exists closed_days    text,            -- วันหยุด
  add column if not exists payment_terms  text,            -- สด/เครดิต
  add column if not exists credit_days    integer,         -- เครดิตกี่วัน
  add column if not exists credit_limit   numeric(12,2),   -- วงเงินเครดิต
  add column if not exists credit_balance numeric(12,2),   -- ยอดค้างชำระ (sync)
  add column if not exists price_tier     text,            -- ระดับราคา/สมาชิก
  add column if not exists total_purchase numeric(14,2),   -- ยอดซื้อรวม (sync จาก Friendship)
  add column if not exists avg_order_value numeric(12,2),  -- ยอดซื้อเฉลี่ย/ครั้ง (sync)
  add column if not exists last_order_date date,           -- ซื้อล่าสุด (sync)
  add column if not exists verified       boolean not null default false, -- ยืนยันข้อมูล/พิกัดแล้ว
  add column if not exists verified_by    uuid references public.profiles(id),
  add column if not exists verified_at    timestamptz,
  add column if not exists updated_by     uuid references public.profiles(id),
  add column if not exists updated_at      timestamptz not null default now();

-- ---------------------------------------------------------------------
-- 2) customer_photos — รูปหลายรูป/ร้าน (ไฟล์อยู่ Storage bucket 'store-photos')
-- ---------------------------------------------------------------------
create table if not exists public.customer_photos (
  id          bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  photo_type  text not null default 'storefront',  -- storefront/owner/interior/access/other
  file_path   text not null,                        -- path ใน bucket store-photos
  caption     text,
  lat         double precision,                     -- พิกัดตอนถ่าย (ยืนยันว่าอยู่หน้าร้าน)
  lng         double precision,
  taken_at    timestamptz,
  taken_by    uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);
create index if not exists idx_cphoto_cust on public.customer_photos(customer_id);

-- ---------------------------------------------------------------------
-- 3) customer_orders — บันทึกยอดซื้อ/ส่งต่อครั้ง (ผูก trip ได้)
--    รายละเอียด SKU อยู่ Friendship; อันนี้เก็บระดับสรุป/ต่อเที่ยว
-- ---------------------------------------------------------------------
create table if not exists public.customer_orders (
  id             bigint generated always as identity primary key,
  customer_id    bigint not null references public.customers(id),
  trip_id        bigint references public.trips(id) on delete set null,
  order_date     date not null default current_date,
  amount         numeric(12,2),
  items_note     text,                              -- สรุปสินค้า (ข้อความ)
  payment_status text default 'paid',               -- paid/credit/partial
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index if not exists idx_corder_cust on public.customer_orders(customer_id, order_date desc);
create index if not exists idx_corder_trip on public.customer_orders(trip_id);

-- ---------------------------------------------------------------------
-- 4) RLS สำหรับ 2 ตารางใหม่
--    อ่าน: ทุกคนที่ login · เพิ่มรูป/บันทึกซื้อ: ทุกคนที่ login (สำรวจภาคสนาม)
--    ลบ/แก้: manager
-- ---------------------------------------------------------------------
alter table public.customer_photos enable row level security;
alter table public.customer_orders enable row level security;

drop policy if exists p_cphoto_read   on public.customer_photos;
create policy p_cphoto_read   on public.customer_photos for select using (auth.uid() is not null);
drop policy if exists p_cphoto_insert on public.customer_photos;
create policy p_cphoto_insert on public.customer_photos for insert with check (auth.uid() is not null);
drop policy if exists p_cphoto_mod    on public.customer_photos;
create policy p_cphoto_mod    on public.customer_photos for update using (public.is_manager());
drop policy if exists p_cphoto_del    on public.customer_photos;
create policy p_cphoto_del    on public.customer_photos for delete using (public.is_manager() or taken_by = auth.uid());

drop policy if exists p_corder_read   on public.customer_orders;
create policy p_corder_read   on public.customer_orders for select using (auth.uid() is not null);
drop policy if exists p_corder_insert on public.customer_orders;
create policy p_corder_insert on public.customer_orders for insert with check (auth.uid() is not null);
drop policy if exists p_corder_mod    on public.customer_orders;
create policy p_corder_mod    on public.customer_orders for all using (public.is_manager()) with check (public.is_manager());

-- ---------------------------------------------------------------------
-- 5) Storage bucket 'store-photos' (ส่วนตัว) + policy
--    ถ้าสร้าง bucket ผ่าน Dashboard แล้ว ข้ามส่วน insert buckets ได้
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('store-photos','store-photos', false)
on conflict (id) do nothing;

drop policy if exists p_sp_read   on storage.objects;
create policy p_sp_read   on storage.objects for select
  using (bucket_id = 'store-photos' and auth.uid() is not null);
drop policy if exists p_sp_insert on storage.objects;
create policy p_sp_insert on storage.objects for insert
  with check (bucket_id = 'store-photos' and auth.uid() is not null);
drop policy if exists p_sp_delete on storage.objects;
create policy p_sp_delete on storage.objects for delete
  using (bucket_id = 'store-photos' and public.is_manager());

-- ---------------------------------------------------------------------
-- ตรวจผล
-- ---------------------------------------------------------------------
-- select column_name from information_schema.columns where table_name='customers' order by ordinal_position;
-- select id,name,name from storage.buckets where id='store-photos';
