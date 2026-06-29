/* ============================================================
   STAR Kidz — shared data layer (Store)
   ------------------------------------------------------------
   Drop-in replacement for the two shared localStorage keys.

     Store.getItem(key)        -> string | null   (synchronous, from cache)
     Store.setItem(key, value) -> void            (writes to cloud or localStorage)
     Store.onChange(key, cb)   -> void            (fires when that key changes anywhere)
     Store.mode()              -> 'firebase' | 'local'

   • If firebase-config.js holds real keys  -> CLOUD mode (Firestore, real-time,
     shared across every device & user).
   • Otherwise -> LOCAL mode (browser localStorage, single device) — identical
     to how the app behaved before Firebase was added. Nothing breaks.

   The app code keeps using the SAME JSON payload shape it always did
   (e.g. {updated, orders} / {updated, statuses}); Store just transports it.
============================================================ */
(function (global) {
  // The documents the apps share with each other. The first two are the
  // Sales<->Production link; more (e.g. the CRM's keys) register at runtime
  // via Store.register(key).
  var KEYS = ['STARKIDZ_SALES_ORDERS', 'STARKIDZ_PROD_STATUS'];

  var cache = {};      // key -> latest JSON string (kept fresh by Firestore listener)
  var listeners = {};  // key -> [callbacks]
  var lastCore = {};   // key -> payload-without-`updated` (to skip no-op writes)
  var subscribed = {}; // key -> true once a Firestore listener is attached
  var useFirebase = false, db = null;

  function emit(key) { (listeners[key] || []).forEach(function (cb) { try { cb(); } catch (e) {} }); }

  // ---- localStorage helpers (fallback + warm start) ----
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  // strip the ever-changing `updated` timestamp so we don't write identical data repeatedly
  function coreOf(v) { try { var o = JSON.parse(v); delete o.updated; return JSON.stringify(o); } catch (e) { return v; } }

  // ---- Google Sheets mirror (optional, read-only copy for reporting) ----
  // If sheets-config.js holds a real Apps Script Web App URL, every cloud write
  // is also POSTed there (fire-and-forget) so the data shows up in a spreadsheet.
  // Firebase remains the source of truth; this never blocks or breaks a save.
  function sheetsUrl() {
    var u = global.SHEETS_MIRROR_URL;
    return (typeof u === 'string' && u.indexOf('PASTE') < 0 && u.indexOf('http') === 0) ? u : null;
  }
  function mirrorToSheets(k, v) {
    var url = sheetsUrl();
    if (!url || typeof fetch !== 'function') return;
    try {
      // text/plain avoids a CORS preflight; Apps Script reads e.postData.contents.
      fetch(url, {
        method: 'POST',
        mode: 'no-cors',
        headers: { 'Content-Type': 'text/plain;charset=utf-8' },
        body: JSON.stringify({ key: k, payload: v, updated: Date.now() })
      }).catch(function () {});
    } catch (e) {}
  }

  // Warm the cache from localStorage so the first paint isn't empty.
  function warm(k) { var v = lsGet(k); if (v && !(k in cache)) cache[k] = v; }

  // Live listener per document — this is what makes every device update in real time.
  function subscribe(k) {
    if (!useFirebase || !db || subscribed[k]) return;
    subscribed[k] = true;
    db.collection('sync').doc(k).onSnapshot(function (snap) {
      var d = snap.data();
      if (d && typeof d.payload === 'string' && d.payload !== cache[k]) {
        cache[k] = d.payload;
        lastCore[k] = coreOf(d.payload);   // don't echo this back as a fresh write
        emit(k);
      }
    }, function () { /* listener error -> stays on last cache */ });
  }

  var Store = {
    getItem: function (k) {
      if (useFirebase) return (k in cache) ? cache[k] : lsGet(k);
      return lsGet(k);
    },
    setItem: function (k, v) {
      cache[k] = v;
      if (useFirebase && db) {
        var core = coreOf(v);
        if (lastCore[k] === core) return;     // real content unchanged -> skip the cloud write
        lastCore[k] = core;
        lsSet(k, v);                          // keep a local copy too (offline / fast restart)
        db.collection('sync').doc(k).set({ payload: v, updated: Date.now() }).catch(function () {});
        mirrorToSheets(k, v);                 // also copy into Google Sheets (if configured)
      } else {
        lsSet(k, v);                          // LOCAL mode: storage event notifies other tabs
      }
    },
    onChange: function (k, cb) {
      (listeners[k] = listeners[k] || []).push(cb);
      if (!useFirebase) {
        global.addEventListener('storage', function (e) { if (e.key === k) cb(); });
      }
    },
    // Add another key to the shared set (e.g. the CRM's data keys). Safe to call
    // in LOCAL mode (no-op beyond warming the cache) and idempotent.
    register: function (k) {
      if (KEYS.indexOf(k) < 0) KEYS.push(k);
      warm(k);
      subscribe(k);
    },
    mode: function () { return useFirebase ? 'firebase' : 'local'; }
  };

  function configured(cfg) {
    return cfg && typeof cfg.apiKey === 'string' && cfg.apiKey.indexOf('PASTE') < 0 && cfg.apiKey.length > 10;
  }

  (function init() {
    var cfg = global.FIREBASE_CONFIG;
    if (!configured(cfg) || typeof firebase === 'undefined') return;   // -> LOCAL mode
    try {
      firebase.initializeApp(cfg);
      db = firebase.firestore();
      useFirebase = true;
      // Anonymous sign-in lets the device talk to Firestore. (Phase 2: real per-user logins.)
      if (firebase.auth) firebase.auth().signInAnonymously().catch(function () {});
      KEYS.forEach(function (k) { warm(k); subscribe(k); });
    } catch (e) { useFirebase = false; db = null; }   // any failure -> safe LOCAL mode
  })();

  global.Store = Store;
})(window);
