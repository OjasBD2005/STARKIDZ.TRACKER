"""Seed departments + the exact identity registry (passwords bcrypt-hashed).
Run once after applying schema.sql:   python seed.py
"""
from sqlalchemy import text
from passlib.hash import bcrypt
from db import engine

DEPTS = [
    "Sales Department", "Production G.M Office", "Upper Department", "P.U Department",
    "P.V.C Department", "Stuckon Department", "Dispatch Department",
    "Global Master Control Override",
]

# (full_name, username, password, department, role, is_master)
USERS = [
    ("RENU",         "RENU",         "9254174722", "Sales Department",                "Sales Staff",     0),
    ("SANJEEV",      "SANJEEV",      "9999534491", "Sales Department",                "Sales Staff",     0),
    ("DHEERAJ",      "DHEERAJ",      "9015087041", "Sales Department",                "Sales Staff",     0),
    ("SHAMSHAD",     "SHAMSHAD",     "9254174708", "Sales Department",                "Sales Staff",     0),
    ("SHUBHAMI",     "SHUBHAMI",     "9254174722", "Sales Department",                "Sales Staff",     0),
    ("KOMAL JAIN",   "KOMAL JAIN",   "9215060303", "Production G.M Office",            "Production G.M",   0),
    ("SUPERVISOR 1", "SUPERVISOR 1", "24-25",      "Upper Department",                "Supervisor",      0),
    ("SUPERVISOR 2", "SUPERVISOR 2", "64-65",      "P.U Department",                  "Supervisor",      0),
    ("SUPERVISOR 3", "SUPERVISOR:3", "24-65",      "P.V.C Department",                "Supervisor",      0),
    ("SUPERVISOR 4", "SUPERVISOR-4", "65-25",      "Stuckon Department",              "Supervisor",      0),
    ("SUPERVISOR 5", "SUPERVISOR :5","64-25",      "Dispatch Department",             "Supervisor",      0),
    ("SUSHIL",       "DISPATCH 1",   "OJAS64",     "Dispatch Department",             "Supervisor",      0),
    ("SANDEEP",      "DISPATCH2",    "OJAS65",     "Dispatch Department",             "Supervisor",      0),
    ("MASTER ID",    "MASTER",       "8920250291", "Global Master Control Override",  "System Master",   1),
]

with engine.begin() as cx:
    for d in DEPTS:
        cx.execute(text("INSERT IGNORE INTO departments(name) VALUES(:n)"), {"n": d})
    deptmap = {name: did for name, did in cx.execute(text("SELECT name, id FROM departments")).all()}
    for full, user, pw, dept, role, master in USERS:
        cx.execute(text("""
            INSERT INTO users (username, full_name, password_hash, department_id, role, is_master)
            VALUES (:u, :f, :p, :d, :r, :m)
            ON DUPLICATE KEY UPDATE
              password_hash=VALUES(password_hash),
              department_id=VALUES(department_id),
              role=VALUES(role), is_master=VALUES(is_master)
        """), {"u": user, "f": full, "p": bcrypt.hash(pw), "d": deptmap[dept], "r": role, "m": master})

print("Seeded %d departments and %d users." % (len(DEPTS), len(USERS)))
