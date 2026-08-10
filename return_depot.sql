-- RouteFlow — คลังปลายทางขากลับ (return depot)
-- พอส่งของครบ คนขับเลือกคลังที่จะกลับเข้า → ระบบตาม GPS ขากลับต่อจนถึงคลัง
-- รันครั้งเดียวใน Supabase → SQL Editor

alter table public.trips add column if not exists return_name text;             -- ชื่อคลังที่กลับเข้า
alter table public.trips add column if not exists return_lat  double precision;  -- พิกัดคลังกลับ
alter table public.trips add column if not exists return_lng  double precision;
alter table public.trips add column if not exists returned_at timestamptz;       -- เวลาถึงคลัง (จบทริปจริง)

comment on column public.trips.return_name is 'คลังที่รถกลับเข้าหลังส่งของครบ (เลือกโดยคนขับ)';
