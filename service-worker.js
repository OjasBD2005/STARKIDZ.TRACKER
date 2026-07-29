/* STAR Kidz — service worker (makes the app installable & usable offline) */
/* Bump CACHE on every release. The name change is what makes `activate` purge the old
   cache, and it also changes this file's bytes, which is how the browser notices there
   is a new worker at all — leave it unchanged and installed PWAs keep the old build. */
var CACHE = 'starkidz-v6';
var CORE = [
  'index.html', 'login.html',
  'ojas-dispatch-tracker.html', 'star-kidz-production-system.html',
  'star-kidz-sales-crm.html',
  'articles-data.js', 'parties-data.js', 'store.js', 'firebase-config.js', 'sheets-config.js',
  'star-loader.js', 'pwa.js',
  'manifest.json', 'icon.svg', 'star-kidz-logo-full.svg'
];

self.addEventListener('install', function (e) {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(function (c) {
    // cache best-effort: never let one missing file fail the whole install
    return Promise.all(CORE.map(function (u) { return c.add(u).catch(function () {}); }));
  }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.map(function (k) { return k === CACHE ? null : caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  // Never cache Firebase / Google APIs or other cross-origin live calls — always go to network.
  if (url.origin !== self.location.origin) return;

  // The app's code and data must never come from the browser's HTTP cache: plain
  // fetch(req) still consults it, so a stale page can survive a deploy (and an
  // installed PWA can sit on an old build for days). For those, re-request the URL
  // with cache:'no-store' so the network is always the source of truth; everything
  // else (icons, images) keeps the cheaper network-first path.
  var fresh = req.mode === 'navigate' || /\.(html|js|json)$/i.test(url.pathname) || url.pathname === '/';

  function store(res) {
    var copy = res.clone();
    caches.open(CACHE).then(function (c) { c.put(req, copy).catch(function () {}); });
    return res;
  }
  function fallback() {
    return caches.match(req).then(function (m) { return m || caches.match('login.html'); });
  }

  e.respondWith(
    (fresh ? fetch(url.href, { cache: 'no-store', credentials: 'same-origin' }) : fetch(req))
      .then(store).catch(fallback)
  );
});
