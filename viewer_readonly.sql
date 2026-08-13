-- ============================================================
-- viewer_readonly.sql
-- ให้ตำแหน่ง viewer "อ่านได้ทุกอย่าง" (read-only) — เขียน/แก้/ลบ ยังถูกบล็อกด้วย write policy เดิม
-- รันครั้งเดียวใน Supabase → SQL Editor
-- ============================================================

-- ใครดูได้ทั้งหมด = ผู้จัดการ (admin/manager/dc_head) หรือ viewer
create or replace function public.can_view_all() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','manager','dc_head','viewer')
                   from public.profiles where id = auth.uid()), false)
$$;

-- profiles: viewer เห็นชื่อทุกคน (ไว้โชว์ชื่อคนขับ/ทีมงาน)
drop policy if exists p_profiles_read on public.profiles;
create policy p_profiles_read on public.profiles for select
  using (id = auth.uid() or public.can_view_all());

-- trips + ตารางที่เกี่ยวข้อง: viewer อ่านได้
drop policy if exists p_trips_read on public.trips;
create policy p_trips_read on public.trips for select
  using (public.can_view_all() or public.in_trip_crew(id));

drop policy if exists p_crew_read on public.trip_crew;
create policy p_crew_read on public.trip_crew for select
  using (public.can_view_all() or user_id = auth.uid());

drop policy if exists p_stops_read on public.trip_stops;
create policy p_stops_read on public.trip_stops for select
  using (public.can_view_all() or public.in_trip_crew(trip_id));

drop policy if exists p_plan_read on public.route_plan_points;
create policy p_plan_read on public.route_plan_points for select
  using (public.can_view_all() or public.in_trip_crew(trip_id));

drop policy if exists p_ping_read on public.gps_pings;
create policy p_ping_read on public.gps_pings for select
  using (public.can_view_all() or public.in_trip_crew(trip_id));

drop policy if exists p_offroute_read on public.off_route_events;
create policy p_offroute_read on public.off_route_events for select
  using (public.can_view_all() or public.in_trip_crew(trip_id));

drop policy if exists p_proof_read on public.delivery_proofs;
create policy p_proof_read on public.delivery_proofs for select
  using (public.can_view_all() or exists(
    select 1 from public.trip_stops s
    where s.id = trip_stop_id and public.in_trip_crew(s.trip_id)
  ));

-- หมายเหตุ: write policy ทุกตารางยังเป็น is_manager()/crew เท่านั้น → viewer สร้าง/แก้/ลบ ไม่ได้
