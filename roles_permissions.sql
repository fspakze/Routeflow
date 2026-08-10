-- RouteFlow — เพิ่มตำแหน่ง "หัวหน้า DC" + ระบบกำหนดสิทธิ์รายตำแหน่ง (แก้ได้เฉพาะ Admin)
-- รันครั้งเดียวใน Supabase → SQL Editor (รันทั้งไฟล์ได้เลย)

-- 1) เพิ่มตำแหน่งใหม่เข้า enum (admin มีอยู่แล้ว) — ปลอดภัย ไม่กระทบข้อมูลเดิม
alter type public.user_role add value if not exists 'dc_head';

-- 2) ให้ "หัวหน้า DC" มีสิทธิ์เขียนระดับผู้จัดการใน RLS (ตัวคุมความปลอดภัยชั้นฐานข้อมูล)
create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','manager','dc_head') from public.profiles where id = auth.uid()), false)
$$;

-- 3) ตารางเมทริกซ์สิทธิ์รายตำแหน่ง (ใช้ text เพื่อเลี่ยงผูกกับ enum โดยตรง)
create table if not exists public.role_permissions (
  role          text primary key,
  label         text,
  can_dashboard boolean not null default false,  -- ดูแดชบอร์ด
  can_plan      boolean not null default false,  -- วางแผน trip
  can_stores    boolean not null default false,  -- จัดการร้านค้า
  can_vehicles  boolean not null default false,  -- จัดการรถ
  can_reports   boolean not null default false,  -- ดูรายงาน
  can_staff     boolean not null default false,  -- จัดการพนักงาน
  can_driver_app boolean not null default false, -- ใช้แอปคนขับ (PWA)
  updated_at    timestamptz not null default now()
);

-- 4) ค่าเริ่มต้นของแต่ละตำแหน่ง (ไม่ทับของเดิมถ้ามีแล้ว)
insert into public.role_permissions (role,label,can_dashboard,can_plan,can_stores,can_vehicles,can_reports,can_staff,can_driver_app) values
  ('admin',  'ผู้ดูแลระบบ',   true, true, true, true, true, true, true ),
  ('manager','ผู้จัดการ',     true, true, true, true, true, true, false),
  ('dc_head','หัวหน้า DC',     true, true, true, true, true, false,false),
  ('driver', 'คนขับ',         false,false,false,false,false,false,true ),
  ('helper', 'ผู้ช่วย',       false,false,false,false,false,false,true ),
  ('viewer', 'ดูอย่างเดียว',  true, false,false,false,true, false,false)
on conflict (role) do nothing;

-- 5) RLS: ทุกคนที่ล็อกอินอ่านได้ (เพื่อให้ UI รู้ว่าตำแหน่งตัวเองทำอะไรได้) · แก้ได้เฉพาะ Admin
alter table public.role_permissions enable row level security;

drop policy if exists rp_read on public.role_permissions;
create policy rp_read on public.role_permissions for select
  using (auth.uid() is not null);

drop policy if exists rp_write on public.role_permissions;
create policy rp_write on public.role_permissions for all
  using (public.current_role() = 'admin')
  with check (public.current_role() = 'admin');

comment on table public.role_permissions is 'เมทริกซ์สิทธิ์รายตำแหน่ง — คุมการแสดง/ใช้งานเมนูใน UI (แก้ได้เฉพาะ admin) · ความปลอดภัยข้อมูลจริงอยู่ที่ RLS ของแต่ละตาราง';
