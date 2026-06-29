/* ============================================================
   STAR Kidz — Google Sheets Mirror (Apps Script Web App)
   ------------------------------------------------------------
   Receives a copy of every cloud save from the app and writes it
   into THIS spreadsheet as readable rows — one tab per data key
   (e.g. STARKIDZ_SALES_ORDERS, STARKIDZ_PROD_STATUS).

   It always rewrites the tab to match the latest data, so the
   sheet is a live mirror of the current state (not an append log).
   A "_log" tab keeps a timestamped history of every save.

   HOW TO INSTALL (one time, ~3 min):
   1. Make a new Google Sheet (sheets.new).
   2. Extensions → Apps Script. Delete the sample code.
   3. Paste this whole file. Save.
   4. Deploy → New deployment → type "Web app".
        • Execute as:  Me
        • Who has access:  Anyone
      Deploy → copy the "Web app URL".
   5. Paste that URL into  sheets-config.js  in the app.
   ============================================================ */

function doPost(e) {
  try {
    var body = JSON.parse(e.postData.contents);
    var key = String(body.key || 'data');
    var payload = body.payload;
    var obj = (typeof payload === 'string') ? JSON.parse(payload) : payload;

    writeMirrorTab(key, obj);
    appendLog(key, body.updated);

    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

// Quick health check when you open the URL in a browser.
function doGet() {
  return json({ ok: true, service: 'STAR Kidz Sheets Mirror', time: new Date() });
}

/* ---- write one tab named after the key, flattened to columns ---- */
function writeMirrorTab(key, obj) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var name = key.substring(0, 90);              // tab names are length-limited
  var sheet = ss.getSheetByName(name) || ss.insertSheet(name);
  sheet.clearContents();

  // Find the first array property in the payload (orders / statuses / etc).
  var rows = null;
  if (Array.isArray(obj)) {
    rows = obj;
  } else if (obj && typeof obj === 'object') {
    for (var p in obj) {
      if (Array.isArray(obj[p])) { rows = obj[p]; break; }
    }
  }

  if (rows && rows.length && typeof rows[0] === 'object') {
    // Build the column set from the union of all row keys (stable order).
    var cols = [];
    rows.forEach(function (r) {
      if (r && typeof r === 'object') {
        for (var c in r) if (cols.indexOf(c) < 0) cols.push(c);
      }
    });
    var out = [cols];
    rows.forEach(function (r) {
      out.push(cols.map(function (c) {
        var val = r ? r[c] : '';
        if (val && typeof val === 'object') val = JSON.stringify(val);
        return (val === undefined || val === null) ? '' : val;
      }));
    });
    sheet.getRange(1, 1, out.length, cols.length).setValues(out);
    sheet.getRange(1, 1, 1, cols.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
  } else {
    // No array to flatten — store the raw JSON so nothing is lost.
    sheet.getRange(1, 1).setValue('Raw JSON');
    sheet.getRange(2, 1).setValue(JSON.stringify(obj, null, 2));
  }
}

/* ---- timestamped history of saves ---- */
function appendLog(key, updated) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var log = ss.getSheetByName('_log');
  if (!log) {
    log = ss.insertSheet('_log');
    log.appendRow(['Received at', 'Key', 'App timestamp']);
    log.getRange(1, 1, 1, 3).setFontWeight('bold');
  }
  log.appendRow([new Date(), key, updated ? new Date(updated) : '']);
}

function json(o) {
  return ContentService
    .createTextOutput(JSON.stringify(o))
    .setMimeType(ContentService.MimeType.JSON);
}
