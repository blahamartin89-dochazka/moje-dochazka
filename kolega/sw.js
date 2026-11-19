const CACHE='moje-dochazka-kolega-2026-11-19.12';
const ASSETS=['./','index.html','manifest.json','config.js'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('moje-dochazka-kolega-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
 const r=e.request;if(r.method!=='GET')return;
 const u=new URL(r.url);if(u.origin!==location.origin)return;
 if(!/\/kolega(\/|$)/.test(u.pathname))return;
 if(r.mode==='navigate'||u.pathname.endsWith('/config.js')){
  const key=r.mode==='navigate'?'index.html':'config.js';
  e.respondWith(fetch(r).then(res=>{const cp=res.clone();if(res.ok)caches.open(CACHE).then(c=>c.put(key,cp));return res}).catch(()=>caches.match(key)));
  return;
 }
 e.respondWith(caches.match(r,{ignoreSearch:true}).then(m=>m||fetch(r)));
});
