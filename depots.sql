-- RouteFlow — คลังต้นทาง (depots) ให้เลือกได้ตอนวางแผน trip
-- รันครั้งเดียวใน Supabase → SQL Editor (รันทั้งไฟล์ได้เลย)

create table if not exists public.depots (
  id         bigint generated always as identity primary key,
  name       text not null unique,
  lat        double precision,
  lng        double precision,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.depots enable row level security;

drop policy if exists dp_read on public.depots;
create policy dp_read on public.depots for select
  using (auth.uid() is not null);

drop policy if exists dp_write on public.depots;
create policy dp_write on public.depots for all
  using (public.is_manager()) with check (public.is_manager());

-- คลังเริ่มต้น 2 จุด (พิกัดยังว่าง — ตั้งได้ในหน้า "จัดการคลัง" ของ admin.html)
insert into public.depots (name) values
  ('Friendship SuperMart'),
  ('Friendship Trading')
on conflict (name) do nothing;

comment on table public.depots is 'คลัง/จุดต้นทางของ trip — เลือกในหน้าวางแผน แล้วเติม origin_name/origin_lat/origin_lng ให้ trip';
