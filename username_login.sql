-- RouteFlow — เพิ่มระบบ "ไอดีเข้าระบบ" (username) แทนการจำอีเมล
-- แนวคิด: พนักงาน login ด้วยไอดีสั้น ๆ (เช่น driver01) ระบบแปลงเป็น <username>@routeflow.local
--         เบื้องหลังก่อนส่งเข้า Supabase Auth (Auth ยังผูกกับอีเมลตามเดิม)
-- รันครั้งเดียวใน Supabase → SQL Editor

alter table public.profiles add column if not exists username text;

-- ไอดีห้ามซ้ำ (ไม่สนตัวพิมพ์ใหญ่-เล็ก) · แถวที่ยังไม่มี username (NULL) ไม่ถือว่าซ้ำกัน
create unique index if not exists profiles_username_key
  on public.profiles (lower(username));

comment on column public.profiles.username is
  'ไอดีสำหรับเข้าระบบ — ระบบแปลงเป็น <username>@routeflow.local ก่อนเข้าสู่ Supabase Auth';

-- (ทางเลือก) ตั้งไอดีให้บัญชีแอดมินเดิมของคุณ เพื่อให้ตารางทีมงานแสดงผลครบ
-- แก้อีเมลให้ตรงกับบัญชีแอดมิน แล้วเอาคอมเมนต์ออกถ้าต้องการ:
-- update public.profiles p set username = u.email
--   from auth.users u where u.id = p.id and p.username is null and p.role = 'admin';
