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
  // The only two documents the two apps share with each other:
  var KEYS = ['STARKIDZ_SALES_ORDERS', 'STARKIDZ_PROD_STATUS'];

  var cache = {};      // key -> latest JSON string (kept fresh by Firestore listener)
  var listeners = {};  // key -> [callbacks]
  var lastCore = {};   // key -> payload-without-`updated` (to skip no-op writes)
  var useFirebase = false, db = null;

  function emit(key) { (listeners[key] || []).forEach(function (cb) { try { cb(); } catch (e) {} }); }

  // ---- localStorage helpers (fallback + warm start) ----
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  // strip the ever-changing `updated` timestamp so we don't write identical data repeatedly
  function coreOf(v) { try { var o = JSON.parse(v); delete o.updated; return JSON.stringify(o); } catch (e) { return v; } }

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
      // Warm the cache from localStorage so the first paint isn't empty.
      KEYS.forEach(function (k) { var v = lsGet(k); if (v) cache[k] = v; });
      // Live listener per shared document — this is what makes every device update in real time.
      KEYS.forEach(function (k) {
        db.collection('sync').doc(k).onSnapshot(function (snap) {
          var d = snap.data();
          if (d && typeof d.payload === 'string' && d.payload !== cache[k]) {
            cache[k] = d.payload;
            lastCore[k] = coreOf(d.payload);   // don't echo this back as a fresh write
            emit(k);
          }
        }, function () { /* listener error -> stays on last cache */ });
      });
    } catch (e) { useFirebase = false; db = null; }   // any failure -> safe LOCAL mode
  })();

  global.Store = Store;
})(window);
