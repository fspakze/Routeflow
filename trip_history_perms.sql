-- ============================================================
-- trip_history_perms.sql
-- เพิ่มสิทธิ์ "แก้ไข / ลบ ประวัติเส้นทาง (trip ย้อนหลัง)" ในตาราง role_permissions
-- รันครั้งเดียวใน Supabase → SQL Editor
-- ============================================================

alter table role_permissions add column if not exists can_edit_trip boolean not null default false;
alter table role_permissions add column if not exists can_del_trip  boolean not null default false;

-- ค่าเริ่มต้น: admin/manager แก้และลบได้, หัวหน้า DC แก้ได้ (ลบไม่ได้)
update role_permissions set can_edit_trip=true, can_del_trip=true  where role in ('admin','manager');
update role_permissions set can_edit_trip=true, can_del_trip=false where role = 'dc_head';

-- หมายเหตุ: RLS ของตาราง trips/trip_stops/trip_crew ยังเป็นด่านจริงเสมอ
-- (is_manager() = admin/manager/dc_head แก้/ลบได้) — สิทธิ์นี้คุมปุ่มบน UI เพิ่มอีกชั้น
