"""
STAR Kidz ERP backend  —  FastAPI + python-socketio + MySQL
Run:  uvicorn main:app --reload --port 8000
Implements: bcrypt login, JWT, session-killing (master exempt), master impersonation,
out-of-stock cross-link, live 4-stage sync, ephemeral 5-min alerts, month-wise reports.
"""
import os, uuid, asyncio
import datetime as dt
import socketio
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from jose import jwt
from passlib.hash import bcrypt
from sqlalchemy import text
from db import engine

SECRET = os.getenv("JWT_SECRET", "change-me-in-prod")
ALGO = "HS256"

sio = socketio.AsyncServer(async_mode="asgi", cors_allowed_origins="*")
api = FastAPI(title="STAR Kidz ERP")
api.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app = socketio.ASGIApp(sio, other_asgi_app=api)        # <-- uvicorn entrypoint: main:app

live_sockets: dict[str, str] = {}                       # jti -> socket id (for instant force-logout)

# ----------------------------- helpers -----------------------------
def make_token(u, jti):
    return jwt.encode(
        {"uid": u["id"], "jti": jti, "role": u["role"], "master": bool(u["is_master"]),
         "exp": dt.datetime.utcnow() + dt.timedelta(hours=12)},
        SECRET, algorithm=ALGO,
    )

def verify(token: str):
    p = jwt.decode(token, SECRET, algorithms=[ALGO])
    if p.get("master"):
        return p                                        # master sessions are never killed
    with engine.connect() as cx:
        ok = cx.execute(text("SELECT 1 FROM sessions WHERE token_jti=:j"), {"j": p["jti"]}).first()
    if not ok:
        raise ValueError("Session terminated")          # killed by a newer login
    return p

def raise_alert(cx, **a):
    aid = str(uuid.uuid4())
    cx.execute(text("""
        INSERT INTO alerts (id, type, title, body, order_id, target_user, target_dept, expires_at)
        VALUES (:id, :t, :ti, :b, :o, :tu, :td, NOW() + INTERVAL 5 MINUTE)
    """), {"id": aid, "t": a.get("type"), "ti": a.get("title"), "b": a.get("body"),
           "o": a.get("order_id"), "tu": a.get("target_user"), "td": a.get("target_dept")})
    return {"id": aid, **a}

# ----------------------------- models -----------------------------
class LoginIn(BaseModel):
    username: str
    password: str
    device: str | None = None

class OrderIn(BaseModel):
    order_no: str; customer_name: str; article_code: str; article_name: str
    category: str; quantity: int; order_date: str; delivery_date: str
    priority: str = "Medium"; is_out_of_stock: bool = False; created_by: int

class StageIn(BaseModel):
    order_id: int; stage: str; state: str; by_user: int

class RawIn(BaseModel):
    order_id: int; required: int; available: int; eta: str | None = None; by_user: int

# =========================== AUTH + SESSION KILLING ===========================
@api.post("/login")
async def login(body: LoginIn):
    with engine.begin() as cx:
        u = cx.execute(text("SELECT * FROM users WHERE username=:u"),
                       {"u": body.username}).mappings().first()
        if not u or not bcrypt.verify(body.password, u["password_hash"]):
            raise HTTPException(401, "Invalid Username or Password")

        jti = str(uuid.uuid4())

        # ---- Concurrency rule: kill prior sessions (MASTER exempt) ----
        if not u["is_master"]:
            olds = cx.execute(text("SELECT token_jti FROM sessions WHERE user_id=:i"),
                              {"i": u["id"]}).mappings().all()
            for s in olds:
                sid = live_sockets.get(s["token_jti"])
                if sid:
                    await sio.emit("force-logout", {"reason": "Signed in on another device"}, to=sid)
                    await sio.disconnect(sid)
                live_sockets.pop(s["token_jti"], None)
            cx.execute(text("DELETE FROM sessions WHERE user_id=:i"), {"i": u["id"]})

        cx.execute(text("INSERT INTO sessions (id, user_id, token_jti, device_info) "
                        "VALUES (:id, :u, :j, :d)"),
                   {"id": str(uuid.uuid4()), "u": u["id"], "j": jti, "d": body.device})
        dept = cx.execute(text("SELECT name FROM departments WHERE id=:d"),
                          {"d": u["department_id"]}).scalar()
        token = make_token(u, jti)

    return {"token": token, "user": {"id": u["id"], "name": u["full_name"], "role": u["role"],
                                     "department": dept, "master": bool(u["is_master"])}}

# =============================== SOCKET.IO ===============================
@sio.event
async def connect(sid, environ, auth):
    try:
        p = verify((auth or {}).get("token", ""))       # rejects killed / invalid sessions
    except Exception:
        return False
    live_sockets[p["jti"]] = sid
    await sio.save_session(sid, p)
    sio.enter_room(sid, f"user:{p['uid']}")
    sio.enter_room(sid, f"role:{p['role']}")
    return True

@sio.event
async def disconnect(sid):
    p = await sio.get_session(sid)
    if p:
        live_sockets.pop(p.get("jti"), None)

@sio.on("master:impersonate")
async def impersonate(sid, data):
    p = await sio.get_session(sid)
    if not p or not p.get("master"):
        return
    sio.enter_room(sid, f"view:{data['targetUserId']}")
    await sio.emit("master:layout", {"viewing": data["targetUserId"]}, to=sid)

# ===================== ORDER CREATE (out-of-stock cross-link) =====================
@api.post("/orders")
async def create_order(o: OrderIn):
    with engine.begin() as cx:
        res = cx.execute(text("""
            INSERT INTO orders (order_no, customer_name, article_code, article_name, category,
                                quantity, order_date, delivery_date, priority, is_out_of_stock,
                                created_by, current_stage)
            VALUES (:no, :c, :ac, :an, :cat, :q, :od, :dd, :pr, :oos, :cb, 'UPPER')
        """), {"no": o.order_no, "c": o.customer_name, "ac": o.article_code, "an": o.article_name,
               "cat": o.category, "q": o.quantity, "od": o.order_date, "dd": o.delivery_date,
               "pr": o.priority, "oos": int(o.is_out_of_stock), "cb": o.created_by})
        oid = res.lastrowid
        for st in ("UPPER", "MOULDING", "PACKING", "DISPATCH"):
            cx.execute(text("INSERT INTO order_stages (order_id, stage) VALUES (:o, :s)"),
                       {"o": oid, "s": st})
        alert = None
        if o.is_out_of_stock:
            alert = raise_alert(cx, type="out_of_stock", order_id=oid,
                                title=f"⚡ Priority: {o.article_code} out of stock",
                                body=f"{o.customer_name} · {o.quantity} prs · deliver by {o.delivery_date}")
    await sio.emit("order:new", {"order_id": oid, "order_no": o.order_no, "alert": alert})
    if alert:
        await sio.emit("alert:new", alert)              # priority line-item on Production/GM window
    return {"id": oid, "order_no": o.order_no}

# ===================== STAGE UPDATE (live mirror to Sales) =====================
@api.post("/stage")
async def stage_update(s: StageIn):
    with engine.begin() as cx:
        cx.execute(text("""UPDATE order_stages SET state=:st, updated_by=:by, updated_at=NOW()
                           WHERE order_id=:o AND stage=:s"""),
                   {"st": s.state, "by": s.by_user, "o": s.order_id, "s": s.stage})
        cx.execute(text("UPDATE orders SET current_stage=:s WHERE id=:o"),
                   {"s": s.stage, "o": s.order_id})
        rows = cx.execute(text("SELECT stage, state FROM order_stages WHERE order_id=:o"),
                          {"o": s.order_id}).all()
        matrix = {st: state for st, state in rows}
    await sio.emit("stage:update", {"order_id": s.order_id, "matrix": matrix})
    await sio.emit("sales:refresh", {"order_id": s.order_id, "matrix": matrix})
    return {"order_id": s.order_id, "matrix": matrix}

# ===================== RAW MATERIAL UPDATE (alert shows mod date) =====================
@api.post("/raw")
async def raw_update(r: RawIn):
    pending = max(0, r.required - r.available)
    with engine.begin() as cx:
        cx.execute(text("""
            INSERT INTO raw_material_status (order_id, required_qty, available_qty, pending_qty,
                                             expected_arrival, modified_by, modified_at)
            VALUES (:o, :req, :av, :pen, :eta, :by, NOW())
            ON DUPLICATE KEY UPDATE required_qty=:req, available_qty=:av, pending_qty=:pen,
                                    expected_arrival=:eta, modified_by=:by, modified_at=NOW()
        """), {"o": r.order_id, "req": r.required, "av": r.available, "pen": pending,
               "eta": r.eta, "by": r.by_user})
        alert = raise_alert(cx, type="raw_modified", order_id=r.order_id,
                            title="Raw material updated",
                            body=f"Modified on {dt.datetime.now():%d %b %Y %H:%M} · {r.available}/{r.required} ready")
    await sio.emit("alert:new", alert)
    return {"ok": True, "pending": pending}

# =============================== REPORTS (Module 3) ===============================
@api.get("/reports/{kind}")
def reports(kind: str):
    view = {"pending": "v_month_pending", "dispatch": "v_month_dispatch",
            "projection": "v_next_month_pendency"}.get(kind)
    if not view:
        raise HTTPException(404, "unknown report")
    with engine.connect() as cx:
        return [dict(r._mapping) for r in cx.execute(text(f"SELECT * FROM {view}")).all()]

# ===================== 5-min alert purge (safety sweep) =====================
@api.on_event("startup")
async def startup():
    async def sweep():
        while True:
            try:
                with engine.begin() as cx:
                    cx.execute(text("DELETE FROM alerts WHERE expires_at < NOW()"))
            except Exception:
                pass
            await asyncio.sleep(60)
    asyncio.create_task(sweep())
