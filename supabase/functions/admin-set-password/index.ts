// RouteFlow — Edge Function: admin-set-password
// ให้ admin/manager ตั้ง/รีเซ็ตรหัสผ่านของพนักงาน (กรณีลืมรหัส)
// ปลอดภัย: service_role ฝั่งเซิร์ฟเวอร์ + ตรวจสิทธิ์คนเรียก
// Deploy: Edge Functions → Deploy a new function → ชื่อ "admin-set-password" → วางโค้ดนี้ → Deploy

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

    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } })
    const { data: { user }, error: ue } = await caller.auth.getUser()
    if (ue || !user) return json({ error: 'unauthorized' }, 401)

    const admin = createClient(url, service)
    const { data: prof } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle()
    if (!prof || !['admin', 'manager'].includes(prof.role))
      return json({ error: 'forbidden: admin/manager เท่านั้น' }, 403)

    const { id, password } = await req.json()
    if (!id || !password) return json({ error: 'ต้องระบุ id + password' }, 400)
    if (String(password).length < 6) return json({ error: 'รหัสผ่านอย่างน้อย 6 ตัว' }, 400)

    // ตั้งรหัสใหม่ + ยืนยันอีเมลให้เลย (กันบัญชีค้างสถานะยังไม่ยืนยัน)
    const { error: e } = await admin.auth.admin.updateUserById(id, { password, email_confirm: true })
    if (e) return json({ error: e.message }, 400)

    return json({ ok: true })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
