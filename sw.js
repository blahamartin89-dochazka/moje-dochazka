const CACHE='moje-dochazka-2026-11-06.1-e95a014286';const ASSETS=['./','index.html','manifest.json','apple-touch-icon.png','icon-192.png','icon-512.png','icon-maskable-512.png','config.js','ka-ching.wav','vendor/supabase.js','vendor/jspdf.umd.min.js','vendor/pdf-assets.js'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET'||new URL(r.url).origin!==location.origin)return;
 if(r.mode==='navigate'||new URL(r.url).pathname.endsWith('/config.js')){const key=r.mode==='navigate'?'index.html':'config.js';e.respondWith(fetch(r).then(res=>{const cp=res.clone();if(res.ok)caches.open(CACHE).then(c=>c.put(key,cp));return res}).catch(()=>caches.match(key)));return}
 e.respondWith(caches.match(r,{ignoreSearch:true}).then(m=>m||fetch(r)))});
