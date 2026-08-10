-- RouteFlow — หลักฐานการส่งให้ครบ (Proof of Delivery)
-- เพิ่มคอลัมน์: ชื่อผู้รับ · ลายเซ็น · ผลการส่ง (ครบ/บางส่วน/ตีกลับ) · เหตุผล
-- รันครั้งเดียวใน Supabase → SQL Editor

alter table public.delivery_proofs add column if not exists received_by text;  -- ชื่อผู้รับของ
alter table public.delivery_proofs add column if not exists signature   text;  -- ลายเซ็น (PNG data URL)
alter table public.delivery_proofs add column if not exists result      text;  -- delivered / partial / returned
alter table public.delivery_proofs add column if not exists reason      text;  -- เหตุผลกรณีบางส่วน/ตีกลับ

comment on column public.delivery_proofs.result is 'ผลการส่ง: delivered=ครบ, partial=บางส่วน, returned=ตีกลับ';
