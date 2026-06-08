import os
from sqlalchemy import create_engine

# mysql+pymysql://USER:PASSWORD@HOST:PORT/DBNAME
DB_URL = os.getenv("DB_URL", "mysql+pymysql://root:password@localhost:3306/starkidz")

engine = create_engine(DB_URL, pool_pre_ping=True, future=True)
