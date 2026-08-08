// RouteFlow — ค่าเชื่อมต่อ Supabase (ฝังในเว็บได้ ปลอดภัย)
// publishable/anon key เป็นข้อมูลสาธารณะโดยการออกแบบ — RLS เป็นตัวกันข้อมูล
// ⚠️ ห้ามใส่ service_role / sb_secret_ ที่นี่เด็ดขาด (อันนั้นอยู่ใน Edge Function เท่านั้น)
window.RF_CONFIG = {
  url: "https://cfpmorlgntfdaskbpcoh.supabase.co",
  anonKey: "sb_publishable_zEJCmppu7vG-k2ExPliduw_afMch2wk"
};
