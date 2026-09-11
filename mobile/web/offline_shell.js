// Only public application assets are cached here. Business data belongs in SQLite.
const CACHE = 'zedbiz-shell-pilot1-v1';
const CORE = ['index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
  'sqlite3.wasm', 'drift_worker.dart.js', 'assets/AssetManifest.bin.json',
  'assets/FontManifest.json', 'assets/fonts/MaterialIcons-Regular.otf',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
  'assets/assets/fonts/NotoSans-Regular.ttf'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(CORE)));
});
self.addEventListener('activate', event => {
  event.waitUntil(Promise.all([
    caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('zedbiz-shell-') && k !== CACHE).map(k => caches.delete(k)))),
    self.clients.claim()
  ]));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.includes('/api/')) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok) {
      const copy = response.clone();
      event.waitUntil(caches.open(CACHE).then(cache => cache.put(event.request, copy)));
    }
    return response;
  }).catch(async () => (await caches.match(event.request)) ||
    (event.request.mode === 'navigate' ? caches.match('index.html') : Response.error())));
});
