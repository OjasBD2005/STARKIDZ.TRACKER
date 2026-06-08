# STAR Kidz — Go Live Guide (cloud data + website + Microsoft Store)

This guide takes the app from "works on one computer" to "real cloud app that every
person can use from any device", then publishes it as a website at **erp.starkidz.co.in**
and as a **Microsoft Store** app. **No coding and no command line needed** — everything
is done in web dashboards.

> ✅ The app already works right now in **LOCAL mode** (data saved only on the one
> computer). It will automatically switch to **CLOUD mode** the moment you finish Step 1.
> So nothing breaks while you set this up.

---

## Step 1 — Create the Firebase database (~5 min)

1. Go to **https://console.firebase.google.com** and sign in with a Google account.
2. Click **Add project** → name it `starkidz` → continue (you can turn Google Analytics
   OFF) → **Create project**.
3. On the left, click **Build → Firestore Database → Create database** →
   choose **Production mode** → pick a location near India (e.g. `asia-south1` Mumbai) → **Enable**.
4. On the left, click **Build → Authentication → Get started** → open the
   **Sign-in method** tab → click **Anonymous** → **Enable** → Save.
5. Click the **⚙️ gear (Project settings)** at the top-left. Scroll to **"Your apps"** →
   click the **`</>` (Web)** icon → give it a nickname `starkidz-web` → **Register app**.
6. Firebase shows a `firebaseConfig = { ... }` block. Copy those 6 values.

### Paste the values
Open **`firebase-config.js`** (in this folder) and replace each `PASTE_…` with the
matching value from Firebase. Save the file. That's it — the app is now cloud-connected.

---

## Step 2 — Lock down the database (~2 min)

In Firebase → **Firestore Database → Rules** tab, replace everything with this and click **Publish**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /sync/{doc} {
      allow read, write: if request.auth != null;
    }
  }
}
```

This means only the app (signed in) can read/write the data — not the public internet.

> The app stores everything in one collection called **`sync`**, in two documents:
> `STARKIDZ_SALES_ORDERS` (orders from Sales) and `STARKIDZ_PROD_STATUS` (production
> progress). You'll see them appear in Firestore once people start using it.

---

## Step 3 — Put it online at erp.starkidz.co.in (~10 min, drag & drop)

Firebase/Cloud needs a real web address (it won't fully work by double-clicking the
file). Easiest no-tools way:

1. Put all the app files into **one folder** (these `.html`, `.js`, `.json`, `.svg` files).
2. Go to **https://app.netlify.com** → sign up (free) → **Add new site → Deploy manually**.
3. **Drag the folder** onto the upload box. Netlify gives you a live URL in seconds
   (like `random-name.netlify.app`) — test it there; cloud sync now works across devices.
4. To use your own address: Netlify → **Domain settings → Add a domain** → enter
   `erp.starkidz.co.in`. Netlify shows a **CNAME** record. Add that record in your
   domain provider (wherever starkidz.co.in is managed). Done — HTTPS is automatic.
5. Back in Firebase → **Authentication → Settings → Authorized domains → Add domain** →
   add both your `*.netlify.app` URL and `erp.starkidz.co.in`.

*(Cloudflare Pages or Vercel work the same way if you prefer them over Netlify.)*

---

## Step 4 — Publish to the Microsoft Store (~20 min)

1. Make sure the site is live (Step 3) — Microsoft needs the URL.
2. Go to **https://www.pwabuilder.com**, paste your URL (`https://erp.starkidz.co.in`),
   click **Start**.
3. It scores the app and lets you **edit the icon/colors** (use the built-in image
   generator if it asks for more icon sizes — upload a 512×512 PNG of the STAR Kidz logo).
4. Click **Package for stores → Windows** → **Generate Package**. Download the `.msix`/zip.
5. You need a **Microsoft Partner Center** account (one-time ~$19, sometimes free for
   businesses): **https://partner.microsoft.com**. Create an app listing and upload the
   package PWABuilder produced. Microsoft reviews it, then it's live in the Store.

> Android/Google Play later: same PWABuilder site → **Package for stores → Android**
> (needs a Google Play Developer account, $25 one-time).

---

## Costs at a glance

| Item | Cost |
|---|---|
| Firebase (database + login) | **Free** for a small team; pay-as-you-grow later |
| Netlify hosting | **Free** |
| Domain `starkidz.co.in` | Already owned |
| Microsoft Partner Center | ~$19 one-time (often waived) |
| Google Play (optional) | $25 one-time |
| Apple App Store (optional) | $99/year |

---

## Phase 2 — recommended once it's running

- **Real per-person logins.** Today the gate is the username/password list in
  `login.html`, and the cloud uses anonymous sign-in. Upgrade to **Firebase
  Authentication** with a real account per employee, then tighten the Firestore rules
  so each role only sees what it should. (This is the proper security step before
  trusting it with sensitive data.)
- **A real PNG app icon** (512×512) for the cleanest Store listing — PWABuilder can
  generate every size from one PNG.
- **Backups / history.** Firestore keeps the live data; consider periodic exports.

---

## How the code is wired (for whoever maintains it)

- `firebase-config.js` — your keys. Placeholder = LOCAL mode; real keys = CLOUD mode.
- `store.js` — the data layer. `Store.getItem/setItem/onChange` replace the old
  `localStorage` calls for the two shared keys. Firestore listeners give real-time
  cross-device updates; falls back to `localStorage` automatically if Firebase isn't
  configured or fails to load.
- `manifest.json`, `service-worker.js`, `pwa.js`, `icon.svg` — make it an installable PWA.
- The two app files (`ojas-dispatch-tracker.html`, `star-kidz-production-system.html`)
  are unchanged in behavior — they just talk to `Store` instead of `localStorage`.
