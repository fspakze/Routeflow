-- ============================================================
-- visit_history_perms.sql — สิทธิ์แก้/ลบ ประวัติเยี่ยมร้าน (sales_visits)
-- รันครั้งเดียวใน Supabase → SQL Editor
-- ============================================================
alter table role_permissions add column if not exists can_edit_visit boolean not null default false;
alter table role_permissions add column if not exists can_del_visit  boolean not null default false;

update role_permissions set can_edit_visit=true, can_del_visit=true  where role in ('admin','manager');
update role_permissions set can_edit_visit=true, can_del_visit=false where role = 'dc_head';
-- RLS ของ sales_visits ยังเป็นด่านจริง (manager/เจ้าของ แก้/ลบได้) — สิทธิ์นี้คุมปุ่มบน UI
