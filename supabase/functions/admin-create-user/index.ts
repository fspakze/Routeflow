// RouteFlow — Edge Function: admin-create-user
// ให้ admin/manager สร้างบัญชีทีมงาน (auth user + profile) จากในแอป
// ปลอดภัย: service_role อยู่ฝั่งเซิร์ฟเวอร์เท่านั้น + ตรวจว่าคนเรียกเป็น admin/manager ก่อน
//
// Deploy (เลือกทางใดทางหนึ่ง):
//  A) Supabase Dashboard → Edge Functions → Create function ชื่อ "admin-create-user" → วางโค้ดนี้ → Deploy
//  B) CLI: supabase functions deploy admin-create-user
// env (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY) Supabase ใส่ให้อัตโนมัติ ไม่ต้องตั้งเอง

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url     = Deno.env.get('SUPABASE_URL')!
    const anon    = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // 1) ตรวจว่าคนเรียกเป็นใคร (จาก JWT ที่ส่งมา)
    const authHeader = req.headers.get('Authorization') || ''
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: ue } = await caller.auth.getUser()
    if (ue || !user) return json({ error: 'unauthorized' }, 401)

    // 2) เช็ค role ของคนเรียก ต้องเป็น admin/manager (ใช้ service_role อ่านข้าม RLS)
    const admin = createClient(url, service)
    const { data: prof } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle()
    if (!prof || !['admin', 'manager'].includes(prof.role))
      return json({ error: 'forbidden: admin/manager เท่านั้น' }, 403)

    // 3) รับข้อมูล + สร้าง user
    const { email, password, full_name, role, phone } = await req.json()
    if (!email || !password || !full_name) return json({ error: 'กรอก email/password/ชื่อ ให้ครบ' }, 400)
    if (String(password).length < 6) return json({ error: 'รหัสผ่านอย่างน้อย 6 ตัว' }, 400)
    const validRole = ['driver', 'helper', 'manager', 'viewer'].includes(role) ? role : 'driver'

    const { data: created, error: ce } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,   // ยืนยันอีเมลอัตโนมัติ = login ได้เลย
    })
    if (ce) return json({ error: ce.message }, 400)

    // 4) สร้าง profile
    const { error: pe } = await admin.from('profiles').insert({
      id: created.user.id, full_name, role: validRole, phone: phone || null,
    })
    if (pe) {
      // rollback user ถ้า insert profile ไม่ผ่าน (กัน user ค้างไม่มี profile)
      await admin.auth.admin.deleteUser(created.user.id)
      return json({ error: pe.message }, 400)
    }

    return json({ ok: true, id: created.user.id })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
