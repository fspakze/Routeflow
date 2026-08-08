-- =====================================================================
-- RouteFlow — migration: เปิดทางให้ PWA คนขับทำงาน (เฟส PWA)
-- รันใน Supabase SQL Editor (Ball รันเอง) · idempotent รันซ้ำได้
-- =====================================================================

-- 1) ให้ crew (คนขับ/ผู้ช่วย) อัปเดต trip "ของตัวเอง" ได้
--    เพื่อกดออกเดินทาง/จบงาน/เปลี่ยนสถานะ (actual_depart, actual_finish, status, stops_done)
--    หมายเหตุ: เป็น row-level (crew แก้ได้ทั้งแถวของ trip ตัวเอง) — ภายในทีมที่เชื่อถือได้
--             ถ้าต้องล็อกไม่ให้แก้ช่องแผน ใช้ trigger กันเพิ่มภายหลังได้
drop policy if exists p_trips_crew_update on public.trips;
create policy p_trips_crew_update on public.trips for update
  using (public.in_trip_crew(id))
  with check (public.in_trip_crew(id));

-- 2) Storage bucket 'proofs' สำหรับรูปหลักฐานส่งของ (ส่วนตัว)
insert into storage.buckets (id, name, public)
values ('proofs','proofs', false)
on conflict (id) do nothing;

drop policy if exists p_pf_read on storage.objects;
create policy p_pf_read on storage.objects for select
  using (bucket_id = 'proofs' and auth.uid() is not null);
drop policy if exists p_pf_insert on storage.objects;
create policy p_pf_insert on storage.objects for insert
  with check (bucket_id = 'proofs' and auth.uid() is not null);

-- ตรวจ
-- select id from storage.buckets where id='proofs';
-- select polname from pg_policies where tablename='trips';
