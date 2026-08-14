-- ============================================================
-- sales_crm.sql — ระบบเยี่ยมร้าน / CRM พนักงานขาย
-- ⚠️ รัน 2 ขั้น (เพราะเพิ่มค่า enum ต้อง commit ก่อนใช้)
-- ============================================================

-- ---------- STEP 1 : เพิ่มตำแหน่ง 'sales' (รันอันนี้ก่อน กด Run) ----------
alter type public.user_role add value if not exists 'sales';


-- ---------- STEP 2 : ตาราง + สิทธิ์ (รันหลัง STEP 1 สำเร็จ) ----------

-- ให้ can_view_all() มีแน่ ๆ (viewer/manager เห็นทั้งหมด) — idempotent
create or replace function public.can_view_all() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','manager','dc_head','viewer')
                   from public.profiles where id = auth.uid()), false)
$$;

create table if not exists public.sales_visits (
  id            bigint generated always as identity primary key,
  customer_id   bigint references public.customers(id) on delete cascade,
  sales_id      uuid   references public.profiles(id),   -- พนักงานขายที่รับผิดชอบ
  plan_date     date,                                     -- วันที่วางแผนเข้าพบ
  purpose       text,                                     -- วัตถุประสงค์ (ขาย/แนะนำ/ติดตาม/เก็บเงิน)
  status        text not null default 'planned',          -- planned / checked_in / done / skipped
  check_in_at   timestamptz,
  check_in_lat  double precision,
  check_in_lng  double precision,
  check_in_dist_m numeric,                                -- ระยะห่างจากพิกัดร้านตอนเช็คอิน (ม.)
  check_out_at  timestamptz,
  result        text,                                     -- ผลการเข้าพบ (ขายได้/สนใจ/ปฏิเสธ/ไม่พบ)
  order_amount  numeric,                                  -- ยอดขาย (ถ้ามี)
  interest      text,                                     -- สิ่งที่ได้จากลูกค้า / ที่สนใจ
  feedback      text,                                     -- feedback / ข้อเสนอแนะ
  next_action   text,                                     -- สิ่งที่ตกลงไว้ / ต้องทำครั้งหน้า
  next_visit_date date,                                   -- นัดหมายครั้งต่อไป
  note          text,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
create index if not exists idx_sv_sales    on public.sales_visits(sales_id, plan_date);
create index if not exists idx_sv_customer on public.sales_visits(customer_id, created_at desc);

alter table public.sales_visits enable row level security;

-- อ่าน: เจ้าของ(พนักงานขาย)เห็นของตัวเอง · manager/viewer เห็นทั้งหมด
drop policy if exists sv_read on public.sales_visits;
create policy sv_read on public.sales_visits for select
  using (sales_id = auth.uid() or public.can_view_all());

-- เพิ่ม: manager มอบหมายให้ใครก็ได้ · พนักงานขายเพิ่มของตัวเอง
drop policy if exists sv_insert on public.sales_visits;
create policy sv_insert on public.sales_visits for insert
  with check (public.is_manager() or sales_id = auth.uid());

-- แก้: manager แก้ได้ทั้งหมด · พนักงานขายแก้ของตัวเอง
drop policy if exists sv_update on public.sales_visits;
create policy sv_update on public.sales_visits for update
  using (public.is_manager() or sales_id = auth.uid())
  with check (public.is_manager() or sales_id = auth.uid());

-- ลบ: manager หรือเจ้าของ
drop policy if exists sv_delete on public.sales_visits;
create policy sv_delete on public.sales_visits for delete
  using (public.is_manager() or sales_id = auth.uid());
