/* STAR Kidz — service worker (makes the app installable & usable offline) */
var CACHE = 'starkidz-v1';
var CORE = [
  'index.html', 'login.html',
  'ojas-dispatch-tracker.html', 'star-kidz-production-system.html',
  'articles-data.js', 'store.js', 'firebase-config.js',
  'manifest.json', 'icon.svg'
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
  // Network-first for our own files so updates show up; fall back to cache when offline.
  e.respondWith(
    fetch(req).then(function (res) {
      var copy = res.clone();
      caches.open(CACHE).then(function (c) { c.put(req, copy).catch(function () {}); });
      return res;
    }).catch(function () { return caches.match(req).then(function (m) { return m || caches.match('login.html'); }); })
  );
});
