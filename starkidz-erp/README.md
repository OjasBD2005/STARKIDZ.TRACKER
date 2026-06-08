# STAR Kidz ERP — Python / MySQL backend

FastAPI + python-socketio + MySQL. React frontend talks to it over REST (`/login`, `/orders`,
`/stage`, `/raw`, `/reports/...`) and a Socket.io channel for real-time sync.

## Setup

```bash
# 1. MySQL — create schema
mysql -u root -p < schema.sql

# 2. Python env
python -m venv .venv
# Windows:  .venv\Scripts\activate     |  macOS/Linux:  source .venv/bin/activate
pip install -r requirements.txt

# 3. Point to your DB (default: root:password@localhost:3306/starkidz)
set DB_URL=mysql+pymysql://USER:PASS@HOST:3306/starkidz      # Windows
export DB_URL=mysql+pymysql://USER:PASS@HOST:3306/starkidz   # macOS/Linux
set JWT_SECRET=some-long-random-string

# 4. Seed the 12 users (passwords bcrypt-hashed from the identity registry)
python seed.py

# 5. Run the API + websocket server
uvicorn main:app --reload --port 8000
```

## What each Module maps to

| Spec | Where |
|---|---|
| M1 · bcrypt login + JWT | `POST /login` |
| M1 · session-killing (master exempt) | `login()` deletes prior `sessions`, emits `force-logout` |
| M1 · master "Global Dashboard Jump" | socket `master:impersonate` → `master:layout` |
| M2.1 · out-of-stock cross-link + raw mod date | `POST /orders` (is_out_of_stock) , `POST /raw` |
| M2.3 · category scrub | `orders.category` ENUM = PU/PVC/Stuckon only |
| M2.4 · 4-stage live mirror | `order_stages` + `POST /stage` → emits `stage:update` / `sales:refresh` |
| M2.5 · 5-min ephemeral alerts | `alerts.expires_at` + startup sweep + client TTL |
| M3 · month-wise reports | `GET /reports/{pending|dispatch|projection}` (SQL views) |

## React frontend
Use the components from the chat (`Login`, `DashboardHeader`, `StageMatrix`, `AlertCenter`).
Point them at this server:

```js
const API = "http://localhost:8000";
const socket = io(API, { auth: { token }, transports: ["websocket"] });
// stages shown in the matrix:
//   UPPER → "Stage 1 · Upper / Stitching"
//   MOULDING → "Stage 2 · Gone to Moulding"
//   PACKING → "Stage 3 · Gone to Packing"
//   DISPATCH → "Stage 4 · Dispatch"
```

> Note: the Production Window renders **only** the tracking board + stage controls — the former
> topmost menu/action bar is removed (Module 2.2).
