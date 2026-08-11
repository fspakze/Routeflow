# HANDOFF — RouteFlow (ระบบขนส่ง)

> อัปเดตล่าสุด: 2026-08-09 · เจ้าของ: Ball — Friendship SuperMart, ปากเซ ลาว
> เอกสารนี้ = สถานะปัจจุบัน + วิธีรับงานต่อ (ดู `SPEC.md` สำหรับสถาปัตยกรรมละเอียด)

---

## 1. ภาพรวม
ระบบติดตามการวิ่งส่งของ: วางแผนเส้นทาง → คนขับเก็บ GPS จริงผ่านมือถือ → ผู้จัดการดูแดชบอร์ด (เวลาออก/ถึงร้าน, ส่งครบไหม, วิ่งนอกเส้นทาง)

**Stack:** Supabase (Postgres + RLS + Auth + Storage + Edge Functions) + static HTML + Leaflet.js
**ไม่มี build step** — เว็บเป็นไฟล์ HTML ล้วน โฮสต์บน GitHub Pages
**PWA ติดตั้งได้** (responsive desktop+mobile) — `manifest.webmanifest` (hub) + `manifest-driver.webmanifest` (คนขับ) + `sw.js` (service worker) + `icon.svg` · ทุกหน้ากด "เพิ่มลงหน้าจอโฮม/ติดตั้ง" ได้
**แผนที่บนมือถือ:** legend หมวดร้าน **ย่อได้** (มือถือย่อไว้ก่อน แตะหัวข้อเพื่อกาง — เลิกบังหมุด) · ปุ่ม **⛶ เต็มจอ** ที่ planMap (admin) และ pickMap (stores) เปิดแผนที่เต็มจอปักหมุด/เลือกร้านได้ไม่ชนกับการเลื่อนหน้า · หน้า stores มีปุ่ม "📌 ใช้ตำแหน่งปัจจุบัน" + แสดงพิกัดสดด้านบนแผนที่

## 2. ลิงก์สำคัญ
| อะไร | ที่ไหน |
|---|---|
| เว็บใช้งานจริง | https://fspakze.github.io/Routeflow/ |
| GitHub repo | https://github.com/fspakze/Routeflow (public, branch `main`) |
| Supabase URL | https://cfpmorlgntfdaskbpcoh.supabase.co |
| โฟลเดอร์ในเครื่อง | `C:\Users\FSTDVICTUSHP2024\ระบบขนส่ง` |

## 3. หน้าเว็บ (ทุกหน้า login = อีเมล+รหัส, จำ session ข้ามหน้า)
| ไฟล์ | หน้าที่ | สิทธิ์ |
|---|---|---|
| `index.html` | หน้าหลัก รวมลิงก์ | ทุกคน |
| `dashboard.html` | trip สด (**ติดตามรถ realtime ทุก 15 วิ**) · แผน vs จริง(ถนนจริง) · นอกเส้นทาง · timeline · PDF · รายงาน | admin/manager |
| `driver.html` | PWA คนขับ: ออกเดินทาง/GPS/เช็คอิน/**POD (รูป+ผู้รับ+ลายเซ็น+ส่งครบ/บางส่วน/ตีกลับ)**/จบงาน | crew ของ trip |
| `admin.html` | วางแผน trip (**+จัดลำดับอัตโนมัติ OSRM**) · จัดการรถ/คลัง · จัดการพนักงาน · สิทธิ์ | admin/manager |
| `stores.html` | จัดการร้าน: เพิ่ม/แก้ · ปักพิกัด · รูป · ประวัติซื้อ | login |
| `map.html` | แผนที่ร้าน 401 จุด · ปรับสี/ขนาด/รูปทรงหมุด · ค้นหา(ชื่อ/รหัส/เบอร์) | login |
| `config.js` | Supabase URL + publishable key (ฝังได้ ปลอดภัย — RLS กันข้อมูล) | — |

## 4. ฐานข้อมูล (Supabase)
**ตาราง (schema.postgres.sql):** profiles, vehicles, customers, trips, trip_crew, trip_stops, route_plan_points, gps_pings, off_route_events, delivery_proofs, notifications, audit_logs + view `v_trip_summary`

**ข้อมูลที่มี:** ลูกค้า **401 ร้าน** (import จาก Google My Maps, 10 หมวด, 12 ร้านมีรหัส FS-)

### สถานะการรัน SQL (รันใน Supabase SQL Editor เอง)
| ไฟล์ | สถานะ | หมายเหตุ |
|---|---|---|
| `schema.postgres.sql` | ✅ รันแล้ว | ตารางหลัก + RLS |
| `customers_import.sql` | ✅ รันแล้ว | 401 ร้าน |
| `customers_profile.sql` | ✅ รันแล้ว | คอลัมน์โปรไฟล์ร้าน + `customer_photos` + `customer_orders` + bucket `store-photos` |
| `driver_phase.sql` | ✅ รันแล้ว | policy ให้คนขับแก้ trip ตัวเอง + bucket `proofs` |
| `username_login.sql` | ✅ รันแล้ว | คอลัมน์ `profiles.username` (login ด้วยไอดีแทนอีเมล) |
| `roles_permissions.sql` | ✅ รันแล้ว | เพิ่ม role `dc_head` + ตาราง `role_permissions` (เมทริกซ์สิทธิ์ แก้ได้เฉพาะ admin) · **รันแยก 2 สเต็ป** (STEP 1 = ALTER TYPE, STEP 2 = ที่เหลือ) |
| `depots.sql` | ✅ รันแล้ว | ตาราง `depots` คลังต้นทาง (เลือกได้ตอนวางแผน) + seed 2 คลัง |
| `pod.sql` | ✅ รันแล้ว | คอลัมน์หลักฐานส่ง (received_by/signature/result/reason) ใน `delivery_proofs` |
| `return_depot.sql` | ✅ รันแล้ว | คลังกลับหลังส่งครบ (`trips.return_name/return_lat/return_lng/returned_at`) |
| `features.sql` | ✅ รันแล้ว | `app_settings` เปิด/ปิดฟีเจอร์ + คอลัมน์ COD (`trip_stops.cod_amount/collected_amount/order_note`) |

## 5. Edge Functions
| ฟังก์ชัน | สถานะ | ใช้ทำ |
|---|---|---|
| `admin-create-user` | ✅ deploy แล้ว | admin สร้างบัญชีพนักงาน |
| `admin-delete-user` | ✅ deploy แล้ว | ปุ่มลบบัญชีพนักงาน |
| `admin-set-password` | ✅ deploy แล้ว | admin ตั้ง/รีเซ็ตรหัสผ่านพนักงาน (ปุ่ม "🔑 รหัส") |

โค้ดอยู่ที่ `supabase/functions/<ชื่อ>/index.ts` · deploy: Edge Functions → Deploy a new function → Via Editor → วางโค้ด → ตั้งชื่อให้ตรง → Deploy (key ที่จำเป็น Supabase ใส่ให้อัตโนมัติ)

## 6. RBAC / สิทธิ์
admin (ทุกอย่าง) · manager (แดชบอร์ด/จัดการ) · **dc_head หัวหน้า DC (สิทธิ์ระดับ manager)** · driver+helper (เห็นเฉพาะ trip ตัวเอง, ส่ง GPS/เช็คอิน) · viewer (อ่าน)
- **login ด้วยไอดี:** พนักงานพิมพ์ไอดีสั้น (เช่น `driver01`) ระบบแปลงเป็น `<id>@routeflow.local` ก่อนส่ง Supabase Auth · พิมพ์ที่มี `@` = ใช้เป็นอีเมลจริง (เช่นแอดมินเดิม) · ไอดีเก็บใน `profiles.username`
- **หน้ากำหนดสิทธิ์** (admin.html แท็บ "🔑 สิทธิ์"): เมทริกซ์ `role_permissions` คุมการแสดง/ใช้เมนูราย role — **แก้ได้เฉพาะ admin** (บังคับด้วย RLS) · เป็น UI-gating ชั้นบน โดยมี RLS ของแต่ละตารางเป็นด่านความปลอดภัยจริง
- **สร้าง profile admin คนแรก** ต้องรัน SQL bootstrap (insert profiles จาก auth.users) เพราะสร้าง user ตัวแรกผ่าน RLS ไม่ได้
- พนักงานที่เหลือ: admin สร้างผ่านแท็บทีมงานใน admin.html

## 7. Deploy (อัปเว็บ)
แก้โค้ด → commit → push เข้า `main` → GitHub Pages อัปเดตอัตโนมัติ 1-2 นาที
```bash
git add -A
git commit -m "อัปเดต ..."
git push
```
> ไม่มี `gh` CLI ในเครื่อง — สร้าง PR ผ่าน GitHub API (git credential) หรือทำงานตรงบน main ก็ได้

## 8. ตรรกะสำคัญ
- **วิ่งนอกเส้นทาง:** ห่างเส้นแผน (origin + จุดส่งตามลำดับ) เกิน **200 ม.** ต่อเนื่อง **≥ 2 นาที** — คำนวณ client-side ใน dashboard.html (point-to-polyline + Haversine)
- **เช็คอินอัตโนมัติ:** driver.html mark "ถึงร้าน" เมื่อ GPS อยู่ในรัศมี `customers.geofence_m` (default 120 ม.)
- **GPS ping:** ทุก ~30 วิ ตอน trip status = live

## 9. ⚠️ ข้อควรระวัง (gotchas)
- **ไฟล์ข้อมูลลูกค้าไม่ขึ้น git** (`customers_import.sql`, `*.kml`, `*.kmz`) — กันด้วย `.gitignore` เพราะ repo เป็น public (ข้อมูลจริงอยู่ใน Supabase)
- **publishable key ใน config.js เป็นสาธารณะได้** — ความปลอดภัยอยู่ที่ RLS ต้องเปิดครบทุกตาราง (ห้ามปิด) · **service_role อยู่ใน Edge Function เท่านั้น**
- **GPS ต้อง HTTPS** — ใช้บนมือถือได้เพราะ Pages เป็น https (localhost ก็ได้) · iOS จำกัด background GPS แนะนำ Android เปิดจอค้าง
- **ลบพนักงานที่อยู่ใน trip_crew ไม่ได้** (FK) → ใช้ปุ่ม "ปิดใช้งาน" แทน
- **เส้นแผน = ถนนจริง (OSRM):** dashboard คำนวณเส้นทางตามถนนจริงผ่าน OSRM (`router.project-osrm.org` ฟรี ไม่ต้องมี key) ใช้ทั้งวาดแผนที่ + ตรวจนอกเส้นทาง (>200ม./2นาที เทียบถนนจริง) · fallback เป็นเส้นตรงถ้าเรียก OSRM ไม่ได้ · OSRM public server เหมาะ dev — ถ้า production หนักควร self-host

## 9.5 ระบบเปิด/ปิดฟีเจอร์ (feature flags)
ตาราง `app_settings` (key/enabled) — **Admin เปิด/ปิดที่ dashboard → ตั้งค่า → "ฟีเจอร์ระบบ"** · ทุกหน้าโหลด flags ตอน login แล้ว gate ฟีเจอร์
- `pod_details` (ปิด) — แสดงผู้รับ/ลายเซ็น/ตีกลับ/ดูรูป ใน timeline แดชบอร์ด
- `orders_cod` (ปิด) — กรอก COD+บิลต่อร้าน (admin) · คนขับกรอกเก็บเงินได้จริง (POD) · สรุป COD (dashboard)
> ปิดอยู่ = ไม่กระทบระบบเดิม · ต้องรัน `features.sql` ก่อนถึงเปิดได้

## 10. งานที่เหลือ (Todo)
> ✅ SQL migration ครบ (customers_profile + driver_phase) · Edge Functions ครบ (create + delete) — **ระบบหลักพร้อมใช้จริงครบวงจร**
1. **LINE แจ้งเตือน** — Edge Function `notify-line` (ยังไม่ทำ) ยิงเข้ากลุ่มผู้จัดการเมื่อวิ่งนอกเส้นทาง/จบงาน · ต้องมี LINE Channel access token · dashboard มีปุ่ม "ส่ง LINE" เรียก `notify-line` รออยู่แล้ว
2. Sync รหัส FS- อีก 389 ร้านกับ Friendship `horeca_customers`
3. (อนาคต) Realtime GPS สดบนแดชบอร์ด, รายงานสรุป, route_plan_points ตามถนนจริง

## 11. ไฟล์ในโปรเจกต์
```
index/dashboard/driver/admin/stores/map .html   ← หน้าเว็บ (responsive + PWA)
config.js                                        ← Supabase config
manifest.webmanifest / manifest-driver.webmanifest ← PWA manifest (hub / คนขับ)
sw.js / icon.svg                                 ← service worker + ไอคอนแอป
schema.postgres.sql                              ← ตาราง+RLS (รันแล้ว)
customers_import.sql                             ← 401 ร้าน (รันแล้ว, gitignored)
customers_profile.sql / driver_phase.sql         ← migration (รันแล้ว)
username_login.sql / roles_permissions.sql        ← migration (รันแล้ว)
supabase/functions/admin-create-user/index.ts    ← deploy แล้ว
supabase/functions/admin-delete-user/index.ts    ← deploy แล้ว
import_customers.mjs / mymaps_full.kml / *.kmz    ← เครื่องมือ import (gitignored)
SPEC.md / HANDOFF.md                             ← เอกสาร
```
