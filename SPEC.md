# RouteFlow — สเปกระบบติดตามเส้นทางวิ่งส่งของ

**Version:** 1.0.0
**Stack:** Supabase (PostgreSQL + RLS + Auth + Storage + Realtime + Edge Functions) + static HTML + Tailwind CSS + Leaflet.js + LINE Messaging API
**Backend:** Supabase project ใหม่ **แยกจาก** Friendship Stock (กันเสี่ยง DB production)
**แหล่งพิกัด GPS:** มือถือคนขับ (PWA) ส่ง ping ทุก ~30 วินาที
**เจ้าของ:** Ball — Friendship SuperMart, ปากเซ ลาว

---

## 1. เป้าหมาย (ตอบโจทย์ผู้ใช้)

| คำถามของผู้ใช้ | ตอบด้วยข้อมูล/ตาราง |
|---|---|
| ออกจากคลังกี่โมง | `trips.actual_depart` |
| ถึงร้านแต่ละร้านกี่โมง | `trip_stops.actual_arrive` / `actual_depart` |
| วิ่งนอกเส้นทางหรือไม่ กี่ครั้ง | `off_route_events`, `trips.off_route_count` |
| ส่งทั้งหมดกี่ร้าน / ครบตามแผนไหม | `trips.stops_done` เทียบ `planned_stops` (view `v_trip_summary`) |
| ทะเบียนรถอะไร | `vehicles.plate_no` ผ่าน `trips.vehicle_id` |
| ไปกันกี่คน / ใครขับ ใครช่วย | `trip_crew` (นับจำนวน + แยก role) |
| หลักฐานการส่ง | `delivery_proofs` (รูป/ลายเซ็น/พิกัดตอนถ่าย) |

---

## 2. สถาปัตยกรรม

```
┌────────────────────┐        ┌─────────────────────────────────────┐
│  มือถือคนขับ (PWA)  │        │   Supabase (RouteFlow project ใหม่)  │
│  - watchPosition/30s│──REST─▶│  - Postgres + RLS                    │
│  - เช็คอินร้าน      │        │  - Auth (roles ใน profiles)          │
│  - ถ่ายรูป/ลายเซ็น  │──────▶ │  - Storage (bucket 'proofs')         │
│  - IndexedDB offline│        │  - Realtime (GPS สดขึ้น dashboard)   │
└────────────────────┘        │  - Edge Function: ตรวจนอกเส้นทาง     │
                              │         └──────────▶ LINE Messaging API│
┌────────────────────┐        └───────────────────┬─────────────────┘
│  หลังบ้าน (Manager) │◀────────REST/Realtime──────┘
│  Dashboard+Leaflet  │
└────────────────────┘
```

**หัวใจ:** ข้อมูล GPS ping จริง — ทุกฟีเจอร์ต่อยอดจากตรงนี้ จึงทำ PWA เก็บข้อมูลให้แม่นก่อน dashboard
**ทำไม Supabase (ไม่ใช่ PHP/MySQL ตาม mockup):** stack เดียวกับ Friendship Stock (Ball คุ้นแล้ว), ได้ Auth+RLS+Storage+Realtime+REST อัตโนมัติ, ไม่ต้องหา hosting PHP/cron เอง

---

## 3. ฝั่งมือถือคนขับ (PWA)

PWA = เว็บที่ติดตั้งบนหน้าจอมือถือได้เหมือนแอป ไม่ต้องขึ้น Store

1. **ส่ง GPS ping** — `navigator.geolocation.watchPosition()` → เก็บลง IndexedDB → sync เข้า Supabase ทุก ~30 วิ (offline-first กันเน็ตหลุด), ส่ง `accuracy_m` เพื่อกรอง ping ที่คลาดเคลื่อน (> ~100 ม.)
2. **เช็คอินร้าน** — เข้า geofence ของร้าน → เด้งปุ่ม "ถึงร้านนี้" → ตั้ง `actual_arrive`
3. **ยืนยันส่งของ** — ถ่ายรูป + ลายเซ็น + หมายเหตุ → upload Storage + insert `delivery_proofs` → stop = `delivered`
4. **ปุ่มออกเดินทาง / จบงาน** — ตั้ง `actual_depart` / `actual_finish`

**ข้อควรระวัง:** iOS จำกัด background GPS ของเว็บ — แนะนำคนขับใช้ Android เปิดหน้าจอค้าง, อนุญาตตำแหน่งตลอดเวลา, ปิดโหมดประหยัดแบตของเบราว์เซอร์

---

## 4. ตรรกะ "วิ่งนอกเส้นทาง" + geofence (หัวใจ)

**นอกเส้นทาง:** ห่างเส้นแผน (`route_plan_points`, คำนวณ point-to-polyline ด้วย Haversine) เกิน **200 ม.** ต่อเนื่อง **≥ 2 นาที** → เปิด 1 `off_route_events` + ยิง LINE ครั้งเดียว; กลับเข้าเส้น (< 200 ม.) → ปิด event, คำนวณ `extra_km`/`extra_min`/`max_dist_m`
รันใน **Edge Function** (cron ทุก 1 นาที หรือ trigger ตอนรับ ping) ใช้ service_role key เขียนข้าม RLS ได้

**Geofence "ถึงร้าน":** ping อยู่ในรัศมี `customers.geofence_m` (default 120 ม.) จากพิกัดร้าน → mark `arrived`

---

## 5. ข้อมูลลูกค้าจาก Google My Maps ★ (ทำแล้ว)

ดึงจาก My Maps (mid `1ofWd-J6aNWhD9Zof8cNIv4PGatNqkA8`) ผ่าน `import_customers.mjs` สำเร็จ:

- **401 ร้าน · 10 หมวด (Folder)** → `customers_import.sql` พร้อมรัน
- หมวด: ร้านโชห่วยฝั่งเหนือ (132), ฝั่งใต้ (112), ตลาดดาวเรือง (40), ร้านส่งคู่แข่ง (31), ลูกค้าฝั่งใต้ (29+26), ลูกค้าฝั่งเหนือ (20), FriendShip (8), ต่างแขวง (2), Delivery New (1)
- **12 ร้านมีรหัส FS-xxxxxx ในชื่อ** → ดึงเข้า `customers.code` อัตโนมัติ (link กับ Friendship `horeca_customers`)
- ⚠️ KML เก็บพิกัดเป็น **lng,lat** (สลับ) — สคริปต์จัดการแล้ว

**Export ที่ถูกต้องจาก My Maps:** Entire map · ❌ ไม่ติ๊ก network link · ✅ ติ๊ก "Export as KML instead of KMZ"
(ไฟล์ KMZ เดิมที่ส่งมาเป็น NetworkLink 410 ไบต์ ไม่มีข้อมูลจริง)

**ต้องตรวจก่อน/หลังรัน:** สุ่มเปิดหมุดใน Leaflet ว่าตรงหน้าร้าน · dedupe ร้านซ้ำ · ปรับ `geofence_m` ร้านในตลาดดาวเรือง (ติดกัน → ลด 60–80 ม.) · field `description` จาก My Maps ส่วนใหญ่เป็นเบอร์โทร (ตอนนี้เก็บใน `address` — จะย้ายไป `phone` ก็ได้)

---

## 6. เชื่อมกับ Friendship Stock (sync ร้าน)

- Friendship อยู่ที่ `D:\Friendship\App นับสตีอค` — backend Supabase มีตาราง `horeca_customers`
- **12 ร้านที่มี FS-code** map ตรงได้ทันทีผ่าน `customers.code`
- **ที่เหลือ 389 ร้าน:** match กับ `horeca_customers` ด้วยชื่อ + พิกัดใกล้กัน แล้วเติม `code` (ขั้น sync — ทำภายหลัง)
- RouteFlow กับ Friendship เป็นคนละ Supabase project — sync ผ่าน export/import หรือ script ไม่แชร์ DB ตรง

---

## 7. การเข้าถึงข้อมูล (แทน API เดิม — ใช้ Supabase JS client)

| งาน | วิธี |
|---|---|
| login | Supabase Auth (`signInWithPassword`) |
| ส่ง ping | `insert` เข้า `gps_pings` (RLS: crew ของ trip เท่านั้น) |
| เช็คอิน/ส่งของ | `update` `trip_stops` |
| อัปโหลดหลักฐาน | Storage `upload` → `insert` `delivery_proofs` |
| dashboard trip วันนี้ | `select` จาก `v_trip_summary` |
| เส้นวิ่งจริง | `select` `gps_pings` order by recorded_at |
| GPS สด | Realtime subscribe `gps_pings` |
| ตรวจนอกเส้นทาง + LINE | Edge Function (service_role) |

---

## 8. LINE Messaging API

- ยิงเมื่อ: นอกเส้นทาง · ส่งช้ากว่าแผนเกิน X นาที · จบ trip (การ์ดสรุป)
- ส่งเข้ากลุ่ม LINE ผู้จัดการ (push group) หรือรายบุคคล (`profiles.line_user_id`), Flex Message + ปุ่มลิงก์ดูแผนที่
- กันสแปม: 1 event = 1 ข้อความ, log `notifications` · เช็คโควต้า LINE OA ฟรีก่อน go-live

---

## 9. RBAC (RLS ใน Postgres)

| Role | สิทธิ์ |
|---|---|
| admin | ทุกอย่าง + จัดการผู้ใช้/รถ/import |
| manager | ดู dashboard ทุก trip, รับแจ้งเตือน, ack เหตุการณ์ |
| driver | เห็นเฉพาะ trip ตัวเอง (ผ่าน `trip_crew`), ส่ง ping/เช็คอิน |
| helper | เหมือน driver |
| viewer | อ่านอย่างเดียว |

policy ทั้งหมดอยู่ใน `schema.postgres.sql` (helper: `is_manager()`, `in_trip_crew()`)

---

## 10. ลำดับการพัฒนา (เฟส)

1. ✅ **เฟส 0 — schema + import** — `schema.postgres.sql` + `customers_import.sql` พร้อมแล้ว (รอ Ball รันใน Supabase)
2. **เฟส 1 — sync code จาก Friendship** (389 ร้านที่เหลือ)
3. **เฟส 2 — PWA คนขับ** (เก็บ GPS + เช็คอิน + หลักฐาน) ← สร้างข้อมูลจริง
4. **เฟส 3 — Edge Function** ตรวจนอกเส้นทาง + สรุป trip + LINE
5. **เฟส 4 — Dashboard หลังบ้าน** + แผนที่ Leaflet (แผน vs จริง) + timeline
6. **เฟส 5 — วางแผนเส้นทาง + จัดการรถ/ผู้ใช้ + รายงาน**

---

## ไฟล์ในโปรเจกต์

| ไฟล์ | สถานะ |
|---|---|
| `schema.postgres.sql` | ✅ Supabase schema + RLS (ใช้จริง) |
| `customers_import.sql` | ✅ 401 ร้าน พร้อมรัน |
| `import_customers.mjs` | ✅ parser KML → SQL |
| `mymaps_full.kml` | ข้อมูลดิบจาก My Maps (401 placemark) |
| `schema.sql` | ⚠️ draft MySQL เดิม — เก็บอ้างอิงเฉยๆ ไม่ใช้ |
| `SPEC.md` | เอกสารนี้ |
