-- ============================================================
-- sales_add_customer.sql
-- ให้พนักงานขาย (sales) เพิ่มร้านใหม่ได้ (INSERT customers) — แก้/ลบ ยังเป็น manager เท่านั้น
-- รันครั้งเดียวใน Supabase → SQL Editor (รันหลัง sales_crm.sql STEP 1 ที่เพิ่ม role 'sales' แล้ว)
-- ============================================================

drop policy if exists p_customers_sales_insert on public.customers;
create policy p_customers_sales_insert on public.customers for insert
  with check (public.is_manager() or public.current_role()::text = 'sales');
