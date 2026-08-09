// RouteFlow — Edge Function: admin-delete-user
// ให้ admin/manager ลบบัญชีทีมงานถาวร (auth user → profile ลบตาม cascade)
// ปลอดภัย: service_role ฝั่งเซิร์ฟเวอร์ + ตรวจสิทธิ์คนเรียก + กันลบตัวเอง
// Deploy: Edge Functions → Deploy a new function → ชื่อ "admin-delete-user" → วางโค้ดนี้ → Deploy

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

    const { id } = await req.json()
    if (!id) return json({ error: 'ต้องระบุ id' }, 400)
    if (id === user.id) return json({ error: 'ลบบัญชีตัวเองไม่ได้' }, 400)

    // ลบ auth user → profile ลบตาม FK cascade
    // ถ้า user ถูกใช้ใน trip_crew (FK) จะลบไม่ได้ → ให้ใช้ปิดใช้งานแทน
    const { error: de } = await admin.auth.admin.deleteUser(id)
    if (de) return json({ error: de.message + ' (ถ้าถูกใช้ใน trip ให้ใช้ปิดใช้งานแทน)' }, 400)

    return json({ ok: true })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
