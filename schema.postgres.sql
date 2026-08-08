-- =====================================================================
-- RouteFlow — ระบบจัดการเส้นทางวิ่งส่งของ
-- Schema สำหรับ Supabase (PostgreSQL 15+)
-- Project: RouteFlow (แยกจาก Friendship Stock)
--
-- วิธีใช้: Ball รันไฟล์นี้เองใน Supabase SQL Editor (ตามธรรมเนียม)
-- แนะนำรันเป็นก้อนตามหัวข้อ (1→9) จะ debug ง่ายกว่ารันรวดเดียว
-- ทุกตารางเปิด RLS — ต้องมี policy ครบก่อน production
-- =====================================================================

-- เวลาไทย/ลาว = UTC+7 (เก็บใน DB เป็น timestamptz, แปลงตอนแสดงผล)

-- ---------------------------------------------------------------------
-- 0) ENUM types
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role     as enum ('admin','manager','driver','helper','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type trip_status   as enum ('planned','live','delayed','alert','done','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type stop_status   as enum ('pending','arrived','delivered','skipped','failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type crew_role     as enum ('driver','helper');
exception when duplicate_object then null; end $$;

do $$ begin
  create type proof_type    as enum ('photo','signature','note');
exception when duplicate_object then null; end $$;

do $$ begin
  create type notif_event   as enum ('off_route','delay','stop_done','trip_done','trip_start','other');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 1) profiles — ผูกกับ auth.users ของ Supabase (RBAC + LINE)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text not null,
  phone         text,
  role          user_role not null default 'viewer',
  line_user_id  text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_profiles_role on public.profiles(role);

-- helper: อ่าน role ของผู้ใช้ปัจจุบัน (ใช้ใน RLS) — SECURITY DEFINER กัน recursion
create or replace function public.current_role()
returns user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','manager') from public.profiles where id = auth.uid()), false)
$$;

-- ---------------------------------------------------------------------
-- 2) vehicles — ทะเบียนรถ + ภาษี/ประกัน
-- ---------------------------------------------------------------------
create table if not exists public.vehicles (
  id               bigint generated always as identity primary key,
  plate_no         text not null unique,          -- เช่น 2กมข-8821
  brand_model      text,                           -- Toyota Hilux Revo
  vehicle_type     text,                           -- กระบะ 4 ล้อ / 6 ล้อ
  capacity_kg      integer,
  tax_expiry       date,
  insurance_expiry date,
  is_active        boolean not null default true,
  note             text,
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3) customers — ร้านค้า (พิกัดจาก My Maps + code map กับ Friendship)
-- ---------------------------------------------------------------------
create table if not exists public.customers (
  id            bigint generated always as identity primary key,
  code          text unique,                       -- รหัสร้าน map กับ horeca_customers (Friendship)
  name          text not null,
  category      text,                              -- ประเภทร้าน (จากหมวด/สีใน My Maps)
  address       text,
  subdistrict   text,                              -- ตำบล
  district      text,                              -- อำเภอ/เมือง
  province      text,                              -- จังหวัด/แขวง
  phone         text,
  lat           double precision,
  lng           double precision,
  geofence_m    smallint not null default 120,     -- รัศมีถือว่า "ถึงร้าน" (เมตร)
  is_active     boolean not null default true,
  source        text default 'mymaps',             -- ที่มาข้อมูล (mymaps/friendship/manual)
  created_at    timestamptz not null default now()
);
create index if not exists idx_customers_geo  on public.customers(lat, lng);
create index if not exists idx_customers_area on public.customers(province, district, subdistrict);

-- ---------------------------------------------------------------------
-- 4) trips — 1 เที่ยว/รถ/วัน (planned vs actual)
-- ---------------------------------------------------------------------
create table if not exists public.trips (
  id               bigint generated always as identity primary key,
  trip_code        text not null unique,           -- TRIP-2569-0512-B
  trip_date        date not null,
  vehicle_id       bigint not null references public.vehicles(id),
  origin_name      text,
  origin_lat       double precision,
  origin_lng       double precision,

  planned_depart   timestamptz,
  planned_stops    smallint not null default 0,
  planned_dist_km  numeric(8,2),

  actual_depart    timestamptz,
  actual_finish    timestamptz,
  actual_dist_km   numeric(8,2),
  stops_done       smallint not null default 0,

  status           trip_status not null default 'planned',
  off_route_count  integer not null default 0,
  note             text,
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_trips_date    on public.trips(trip_date);
create index if not exists idx_trips_status  on public.trips(status);
create index if not exists idx_trips_vehicle on public.trips(vehicle_id);

-- ---------------------------------------------------------------------
-- 5) trip_crew — คนขับ+ผู้ช่วย (ตอบ "ไปกันกี่คน")
-- ---------------------------------------------------------------------
create table if not exists public.trip_crew (
  id         bigint generated always as identity primary key,
  trip_id    bigint not null references public.trips(id) on delete cascade,
  user_id    uuid   not null references public.profiles(id),
  crew_role  crew_role not null,
  unique (trip_id, user_id)
);
create index if not exists idx_crew_trip on public.trip_crew(trip_id);
create index if not exists idx_crew_user on public.trip_crew(user_id);

-- ---------------------------------------------------------------------
-- 6) trip_stops — จุดส่ง (แผน vs จริง ต่อร้าน)
-- ---------------------------------------------------------------------
create table if not exists public.trip_stops (
  id            bigint generated always as identity primary key,
  trip_id       bigint not null references public.trips(id) on delete cascade,
  customer_id   bigint not null references public.customers(id),
  seq           smallint not null,                 -- ลำดับส่ง 1,2,3...
  planned_eta   timestamptz,
  actual_arrive timestamptz,
  actual_depart timestamptz,
  dwell_min     smallint,
  status        stop_status not null default 'pending',
  note          text,
  unique (trip_id, seq)
);
create index if not exists idx_stops_trip   on public.trip_stops(trip_id);
create index if not exists idx_stops_status on public.trip_stops(status);

-- ---------------------------------------------------------------------
-- 7) route_plan_points — polyline เส้นทางวางแผน
-- ---------------------------------------------------------------------
create table if not exists public.route_plan_points (
  id       bigint generated always as identity primary key,
  trip_id  bigint not null references public.trips(id) on delete cascade,
  seq      integer not null,
  lat      double precision not null,
  lng      double precision not null
);
create index if not exists idx_plan_trip on public.route_plan_points(trip_id, seq);

-- ---------------------------------------------------------------------
-- 8) gps_pings — พิกัดวิ่งจริง (ตารางใหญ่สุด โตเร็ว)
--    * ระยะยาวควรทำ partition รายเดือน หรือย้ายข้อมูลเก่าเข้า archive
-- ---------------------------------------------------------------------
create table if not exists public.gps_pings (
  id              bigint generated always as identity primary key,
  trip_id         bigint not null references public.trips(id) on delete cascade,
  user_id         uuid references public.profiles(id),
  lat             double precision not null,
  lng             double precision not null,
  speed_kmh       numeric(5,1),
  accuracy_m      numeric(6,1),                     -- กรอง ping ห่วย (>100ม.) ได้
  recorded_at     timestamptz not null,            -- เวลาวัดจากมือถือ
  is_off_route    boolean not null default false,
  dist_to_route_m numeric(8,1),
  created_at      timestamptz not null default now()
);
create index if not exists idx_ping_trip_time on public.gps_pings(trip_id, recorded_at);
create index if not exists idx_ping_offroute  on public.gps_pings(trip_id, is_off_route);

-- ---------------------------------------------------------------------
-- 9) off_route_events — เหตุการณ์วิ่งนอกเส้นทาง
--    เกิดเมื่อ ห่างเส้นแผน >200ม. ต่อเนื่อง >=2นาที
-- ---------------------------------------------------------------------
create table if not exists public.off_route_events (
  id            bigint generated always as identity primary key,
  trip_id       bigint not null references public.trips(id) on delete cascade,
  started_at    timestamptz not null,
  ended_at      timestamptz,                        -- null = ยังอยู่นอกเส้นทาง
  max_dist_m    numeric(8,1),
  extra_km      numeric(8,2),
  extra_min     smallint,
  near_seq      smallint,                           -- ช่วงก่อนถึงจุดส่งที่เท่าไหร่
  peak_lat      double precision,
  peak_lng      double precision,
  acknowledged  boolean not null default false,
  ack_by        uuid references public.profiles(id),
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_offroute_trip on public.off_route_events(trip_id);

-- ---------------------------------------------------------------------
-- 10) delivery_proofs — หลักฐานส่ง (ไฟล์อยู่ Supabase Storage bucket 'proofs')
-- ---------------------------------------------------------------------
create table if not exists public.delivery_proofs (
  id           bigint generated always as identity primary key,
  trip_stop_id bigint not null references public.trip_stops(id) on delete cascade,
  proof_type   proof_type not null,
  file_path    text,                                -- path ใน Storage
  captured_lat double precision,
  captured_lng double precision,
  captured_at  timestamptz,
  captured_by  uuid references public.profiles(id),
  text_note    text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_proof_stop on public.delivery_proofs(trip_stop_id);

-- ---------------------------------------------------------------------
-- 11) notifications — log LINE (กันส่งซ้ำ)
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id          bigint generated always as identity primary key,
  trip_id     bigint references public.trips(id) on delete cascade,
  event_type  notif_event not null,
  target      text,                                 -- line_user_id / group id
  payload     jsonb,
  status      text not null default 'queued',       -- queued/sent/failed
  error_msg   text,
  sent_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists idx_notif_trip   on public.notifications(trip_id);
create index if not exists idx_notif_status on public.notifications(status);

-- ---------------------------------------------------------------------
-- 12) audit_logs
-- ---------------------------------------------------------------------
create table if not exists public.audit_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid references public.profiles(id),
  action     text not null,
  entity     text,
  entity_id  bigint,
  detail     jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_audit_entity on public.audit_logs(entity, entity_id);

-- =====================================================================
-- VIEW สรุป trip — ตอบ "ส่งครบตามแผนไหม + นอกเส้นทางกี่ครั้ง + ไปกี่คน"
-- =====================================================================
create or replace view public.v_trip_summary as
select
  t.id,
  t.trip_code,
  t.trip_date,
  v.plate_no,
  t.planned_stops,
  t.stops_done,
  (t.planned_stops - t.stops_done)                              as stops_missing,
  round(t.stops_done::numeric / nullif(t.planned_stops,0) * 100, 1) as complete_pct,
  t.planned_dist_km,
  t.actual_dist_km,
  (t.actual_dist_km - t.planned_dist_km)                        as extra_km,
  t.off_route_count,
  t.actual_depart,
  t.actual_finish,
  (select count(*) from public.trip_crew c where c.trip_id = t.id) as crew_count,
  t.status
from public.trips t
join public.vehicles v on v.id = t.vehicle_id;

-- =====================================================================
-- ROW LEVEL SECURITY
-- แนวคิด: manager/admin เห็น/แก้ทุก trip · driver+helper เห็นเฉพาะ trip
--         ที่ตัวเองอยู่ใน trip_crew · viewer อ่านอย่างเดียว
-- =====================================================================
alter table public.profiles          enable row level security;
alter table public.vehicles          enable row level security;
alter table public.customers         enable row level security;
alter table public.trips             enable row level security;
alter table public.trip_crew         enable row level security;
alter table public.trip_stops        enable row level security;
alter table public.route_plan_points enable row level security;
alter table public.gps_pings         enable row level security;
alter table public.off_route_events  enable row level security;
alter table public.delivery_proofs   enable row level security;
alter table public.notifications     enable row level security;
alter table public.audit_logs        enable row level security;

-- helper: user นี้อยู่ใน crew ของ trip นี้ไหม
create or replace function public.in_trip_crew(_trip_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.trip_crew c
                where c.trip_id = _trip_id and c.user_id = auth.uid())
$$;

-- profiles: อ่านของตัวเอง / manager อ่านทุกคน; แก้ได้เฉพาะ manager
drop policy if exists p_profiles_read on public.profiles;
create policy p_profiles_read on public.profiles for select
  using (id = auth.uid() or public.is_manager());
drop policy if exists p_profiles_write on public.profiles;
create policy p_profiles_write on public.profiles for all
  using (public.is_manager()) with check (public.is_manager());

-- vehicles / customers: ทุกคนที่ login อ่านได้ · เฉพาะ manager แก้
drop policy if exists p_vehicles_read on public.vehicles;
create policy p_vehicles_read on public.vehicles for select using (auth.uid() is not null);
drop policy if exists p_vehicles_write on public.vehicles;
create policy p_vehicles_write on public.vehicles for all
  using (public.is_manager()) with check (public.is_manager());

drop policy if exists p_customers_read on public.customers;
create policy p_customers_read on public.customers for select using (auth.uid() is not null);
drop policy if exists p_customers_write on public.customers;
create policy p_customers_write on public.customers for all
  using (public.is_manager()) with check (public.is_manager());

-- trips: manager ทุก trip · crew เฉพาะ trip ตัวเอง (อ่าน) · manager เท่านั้นที่สร้าง/แก้ส่วนแผน
drop policy if exists p_trips_read on public.trips;
create policy p_trips_read on public.trips for select
  using (public.is_manager() or public.in_trip_crew(id));
drop policy if exists p_trips_write on public.trips;
create policy p_trips_write on public.trips for all
  using (public.is_manager()) with check (public.is_manager());

-- trip_crew
drop policy if exists p_crew_read on public.trip_crew;
create policy p_crew_read on public.trip_crew for select
  using (public.is_manager() or user_id = auth.uid());
drop policy if exists p_crew_write on public.trip_crew;
create policy p_crew_write on public.trip_crew for all
  using (public.is_manager()) with check (public.is_manager());

-- trip_stops: crew อ่าน+อัปเดตสถานะจุดส่ง (เช็คอิน/ส่งของ) ของ trip ตัวเอง
drop policy if exists p_stops_read on public.trip_stops;
create policy p_stops_read on public.trip_stops for select
  using (public.is_manager() or public.in_trip_crew(trip_id));
drop policy if exists p_stops_update on public.trip_stops;
create policy p_stops_update on public.trip_stops for update
  using (public.is_manager() or public.in_trip_crew(trip_id))
  with check (public.is_manager() or public.in_trip_crew(trip_id));
drop policy if exists p_stops_mgr_write on public.trip_stops;
create policy p_stops_mgr_write on public.trip_stops for all
  using (public.is_manager()) with check (public.is_manager());

-- route_plan_points: crew อ่าน · manager แก้
drop policy if exists p_plan_read on public.route_plan_points;
create policy p_plan_read on public.route_plan_points for select
  using (public.is_manager() or public.in_trip_crew(trip_id));
drop policy if exists p_plan_write on public.route_plan_points;
create policy p_plan_write on public.route_plan_points for all
  using (public.is_manager()) with check (public.is_manager());

-- gps_pings: crew ของ trip insert ping ของตัวเองได้ · อ่านได้เฉพาะ trip ตัวเอง/manager
drop policy if exists p_ping_insert on public.gps_pings;
create policy p_ping_insert on public.gps_pings for insert
  with check (public.in_trip_crew(trip_id) and user_id = auth.uid());
drop policy if exists p_ping_read on public.gps_pings;
create policy p_ping_read on public.gps_pings for select
  using (public.is_manager() or public.in_trip_crew(trip_id));

-- off_route_events: อ่าน crew/manager · เขียนโดย service (Edge Function) หรือ manager
drop policy if exists p_offroute_read on public.off_route_events;
create policy p_offroute_read on public.off_route_events for select
  using (public.is_manager() or public.in_trip_crew(trip_id));
drop policy if exists p_offroute_write on public.off_route_events;
create policy p_offroute_write on public.off_route_events for all
  using (public.is_manager()) with check (public.is_manager());

-- delivery_proofs: crew ของ trip เพิ่มหลักฐานได้ · อ่าน crew/manager
drop policy if exists p_proof_insert on public.delivery_proofs;
create policy p_proof_insert on public.delivery_proofs for insert
  with check (exists(
    select 1 from public.trip_stops s
    where s.id = trip_stop_id and public.in_trip_crew(s.trip_id)
  ));
drop policy if exists p_proof_read on public.delivery_proofs;
create policy p_proof_read on public.delivery_proofs for select
  using (public.is_manager() or exists(
    select 1 from public.trip_stops s
    where s.id = trip_stop_id and public.in_trip_crew(s.trip_id)
  ));

-- notifications / audit_logs: manager อ่าน · เขียนโดย service role (bypass RLS อยู่แล้ว)
drop policy if exists p_notif_read on public.notifications;
create policy p_notif_read on public.notifications for select using (public.is_manager());
drop policy if exists p_audit_read on public.audit_logs;
create policy p_audit_read on public.audit_logs for select using (public.is_manager());

-- หมายเหตุ: Edge Function / งานเบื้องหลัง ใช้ service_role key ซึ่ง bypass RLS
--          จึงเขียน off_route_events, notifications, อัปเดตสรุป trip ได้โดยตรง

-- =====================================================================
-- Storage bucket สำหรับรูปหลักฐาน (รันใน SQL ได้ หรือสร้างผ่าน Dashboard)
-- =====================================================================
-- insert into storage.buckets (id, name, public) values ('proofs','proofs', false)
--   on conflict (id) do nothing;
