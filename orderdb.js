/* ============================================================================
   STAR Kidz — orderdb.js
   One simple "door" to the orders data, used by BOTH the Sales screen and the
   Production screen. It works in two modes automatically:

     • CLOUD mode  -> Firebase Firestore  (real-time, shared across all devices)
     • LOCAL mode  -> browser localStorage (offline testing, even across two
                       windows of the same browser)

   It decides the mode from store.js  ->  Store.mode().
   So: real Firebase keys in firebase-config.js  =  CLOUD; placeholders = LOCAL.

   ----------------------------------------------------------------------------
   LOAD ORDER (in your HTML, before your app code):
     firebase-app-compat.js
     firebase-firestore-compat.js
     firebase-auth-compat.js
     firebase-config.js
     store.js
     orderdb.js     <-- this file
     (then your page script)

   ----------------------------------------------------------------------------
   ONE ORDER LOOKS LIKE THIS (the "schema"):
     {
       orderId, party_name, article_no, quantity, category,
       salespersonId, salespersonName,
       managerId, assignedSupervisorId, assignedSupervisorName,
       status: { upperRawMaterial, moulding, packing, dispatch },  // each: Pending|In Progress|Done
       stage, createdAt, updatedAt
     }
   ----------------------------------------------------------------------------
   QUICK USAGE:
     // Sales submits:
     OrderDB.create(OrderDB.newOrder({ orderId:'ORD-1042', party_name:'Sharma', ... }));

     // Komal watches every order (newest first):
     const stop = OrderDB.listen(null, renderManagerView);

     // Komal allots one to a supervisor:
     OrderDB.allot(id, { supervisorId, supervisorName, managerId });

     // Supervisor ticks a checkpoint:
     OrderDB.setCheckpoint(id, 'moulding', 'Done');

     // Salesperson watches only THEIR orders:
     const stop = OrderDB.listen({ field:'salespersonId', value: myUid }, renderSalesPipeline);

     // Stop a listener (e.g. on logout):  stop();
============================================================================ */
(function (global) {

  // The 4 production checkpoints, in order. Use these names everywhere.
  var CHECKPOINTS = ['upperRawMaterial', 'moulding', 'packing', 'dispatch'];

  // Where local-mode orders live in the browser.
  var LOCAL_KEY = 'STARKIDZ_ORDERS_LOCAL';
  var LOCAL_EVT = 'orderdb:local';   // our own "something changed" signal (same tab)

  // -------------------------------------------------------------------------
  //  MODE + small helpers
  // -------------------------------------------------------------------------
  function isCloud() { return global.Store && Store.mode() === 'firebase' && typeof firebase !== 'undefined'; }
  function fdb()     { return firebase.firestore(); }                 // the Firestore handle
  function uid()     { try { return firebase.auth().currentUser.uid; } catch (e) { return null; } }

  // A timestamp that works in both modes (cloud = Google's clock; local = this device).
  function nowCloud() { return firebase.firestore.FieldValue.serverTimestamp(); }
  function nowLocal() { return Date.now(); }

  // Turn any timestamp (Firestore Timestamp object, number, or null) into milliseconds,
  // so we can sort "newest first" no matter the mode.
  function timeOf(v) {
    if (!v) return 0;
    if (typeof v === 'number') return v;
    if (typeof v.toMillis === 'function') return v.toMillis();   // Firestore Timestamp
    if (v.seconds) return v.seconds * 1000;
    return 0;
  }

  function newId() { return 'local-' + Date.now() + '-' + Math.floor(Math.random() * 1000); }

  // -------------------------------------------------------------------------
  //  LOCAL store read/write (used only in LOCAL mode)
  // -------------------------------------------------------------------------
  function localReadAll() {
    try { return JSON.parse(localStorage.getItem(LOCAL_KEY) || '[]'); } catch (e) { return []; }
  }
  function localWriteAll(arr) {
    try { localStorage.setItem(LOCAL_KEY, JSON.stringify(arr)); } catch (e) {}
    // Tell listeners in THIS tab (localStorage 'storage' event only fires in OTHER tabs).
    try { global.dispatchEvent(new Event(LOCAL_EVT)); } catch (e) {}
  }

  // Apply a "changes" object to a plain order, understanding dotted keys like 'status.moulding'.
  function applyChanges(order, changes) {
    Object.keys(changes).forEach(function (key) {
      var val = changes[key];
      if (key.indexOf('.') >= 0) {                 // nested path, e.g. status.moulding
        var parts = key.split('.');
        var node = order;
        for (var i = 0; i < parts.length - 1; i++) {
          if (typeof node[parts[i]] !== 'object' || node[parts[i]] === null) node[parts[i]] = {};
          node = node[parts[i]];
        }
        node[parts[parts.length - 1]] = val;
      } else {
        order[key] = val;
      }
    });
    return order;
  }

  // -------------------------------------------------------------------------
  //  PUBLIC API
  // -------------------------------------------------------------------------
  var OrderDB = {
    CHECKPOINTS: CHECKPOINTS,
    mode: function () { return isCloud() ? 'firebase' : 'local'; },

    /* Build a fresh order object with sensible defaults + the 4 checkpoints set to "Pending".
       Pass in whatever you have; the rest is filled for you. */
    newOrder: function (data) {
      data = data || {};
      return {
        orderId:        data.orderId        || '',
        party_name:     data.party_name     || '',
        article_no:     data.article_no     || '',
        quantity:       Number(data.quantity || 0),
        category:       data.category       || 'PU',

        salespersonId:   data.salespersonId   || uid(),               // who is logged in now
        salespersonName: data.salespersonName || '',
        managerId:             data.managerId             || null,
        assignedSupervisorId:  data.assignedSupervisorId  || null,
        assignedSupervisorName:data.assignedSupervisorName|| null,

        status: {
          upperRawMaterial: 'Pending',
          moulding:         'Pending',
          packing:          'Pending',
          dispatch:         'Pending'
        },
        stage: 'New'
      };
    },

    /* CREATE a new order. Returns a Promise that resolves to the new document id.
       (Komal's listening screen will show it within ~1 second — no refresh needed.) */
    create: function (order) {
      if (isCloud()) {
        order.createdAt = nowCloud();
        order.updatedAt = nowCloud();
        return fdb().collection('orders').add(order).then(function (ref) { return ref.id; });
      }
      // LOCAL mode
      var all = localReadAll();
      order.id = newId();
      order.createdAt = nowLocal();
      order.updatedAt = nowLocal();
      all.unshift(order);
      localWriteAll(all);
      return Promise.resolve(order.id);
    },

    /* UPDATE any fields on one order. `changes` may use dotted keys for nested fields,
       e.g. { 'status.packing': 'In Progress', stage: 'In Production' }.
       `updatedAt` is set for you. */
    update: function (id, changes) {
      changes = Object.assign({}, changes);   // copy so we don't mutate the caller's object
      if (isCloud()) {
        changes.updatedAt = nowCloud();
        return fdb().collection('orders').doc(id).update(changes);
      }
      // LOCAL mode
      changes.updatedAt = nowLocal();
      var all = localReadAll();
      var o = all.find(function (x) { return x.id === id; });
      if (o) applyChanges(o, changes);
      localWriteAll(all);
      return Promise.resolve();
    },

    /* CONVENIENCE: Komal allots an order to a supervisor. */
    allot: function (id, opts) {
      return OrderDB.update(id, {
        managerId:              opts.managerId || uid(),
        assignedSupervisorId:   opts.supervisorId,
        assignedSupervisorName: opts.supervisorName,
        stage: 'Assigned'
      });
    },

    /* CONVENIENCE: a supervisor sets one checkpoint. value = Pending | In Progress | Done. */
    setCheckpoint: function (id, checkpoint, value) {
      if (CHECKPOINTS.indexOf(checkpoint) < 0) {
        return Promise.reject(new Error('Unknown checkpoint: ' + checkpoint));
      }
      var changes = {};
      changes['status.' + checkpoint] = value;         // dotted path = change ONLY this checkpoint
      if (checkpoint === 'dispatch' && value === 'Done') changes.stage = 'Done';
      else changes.stage = 'In Production';
      return OrderDB.update(id, changes);
    },

    /* DELETE an order (optional). */
    remove: function (id) {
      if (isCloud()) return fdb().collection('orders').doc(id).delete();
      localWriteAll(localReadAll().filter(function (x) { return x.id !== id; }));
      return Promise.resolve();
    },

    /* LISTEN in real-time. This is the heart of the "automatic" updating.
         filter = null                              -> ALL orders (use on Komal's screen)
         filter = { field:'salespersonId', value }  -> only that person's orders (Sales screen)
         filter = { field:'assignedSupervisorId', value } -> a supervisor's assigned orders
       `cb(orders)` is called immediately with the current list, then again on EVERY change.
       Returns a function — call it to stop listening (e.g. on logout). */
    listen: function (filter, cb) {
      if (isCloud()) {
        var q = fdb().collection('orders');
        if (filter) q = q.where(filter.field, '==', filter.value);   // server-side filter
        // We sort in JavaScript (below) so you don't have to create a Firestore index.
        return q.onSnapshot(function (snap) {
          var arr = [];
          snap.forEach(function (d) { arr.push(Object.assign({ id: d.id }, d.data())); });
          arr.sort(function (a, b) { return timeOf(b.createdAt) - timeOf(a.createdAt); }); // newest first
          cb(arr);
        }, function (err) { console.warn('[OrderDB] listen error:', err && err.message); });
      }

      // LOCAL mode: read now, then re-read whenever anything changes (this tab OR another window).
      var read = function () {
        var arr = localReadAll();
        if (filter) arr = arr.filter(function (o) { return o[filter.field] === filter.value; });
        arr.sort(function (a, b) { return timeOf(b.createdAt) - timeOf(a.createdAt); });
        cb(arr);
      };
      var onStorage = function (e) { if (e.key === LOCAL_KEY) read(); };   // other browser windows
      global.addEventListener(LOCAL_EVT, read);
      global.addEventListener('storage', onStorage);
      read();
      return function stop() {
        global.removeEventListener(LOCAL_EVT, read);
        global.removeEventListener('storage', onStorage);
      };
    }
  };

  global.OrderDB = OrderDB;
})(window);
