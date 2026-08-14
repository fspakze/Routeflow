/* RouteFlow — Service Worker (ทำให้ติดตั้งเป็นแอปได้ + shell offline)
   network-first สำหรับไฟล์ในโดเมนเรา · ปล่อยให้ Supabase/CDN วิ่งผ่านปกติ */
const CACHE = 'routeflow-v3';
const CORE = [
  './','./index.html','./dashboard.html','./admin.html','./stores.html','./map.html','./driver.html','./sales.html',
  './config.js','./manifest.webmanifest','./manifest-sales.webmanifest','./icon.svg'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE).catch(()=>{})).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;          // Supabase/CDN → เครือข่ายตามปกติ
  e.respondWith(
    fetch(req, { cache: 'no-store' }).then(res => {   // ดึงไฟล์ใหม่เสมอเมื่อออนไลน์ (กันหน้าค้างเวอร์ชันเก่า)
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(req, copy)).catch(()=>{});
      return res;
    }).catch(() => caches.match(req).then(m => m || caches.match('./index.html')))
  );
});
