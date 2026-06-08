-- ============================================================
-- STAR Kidz ERP — MySQL 8 schema
-- Out-of-stock cross-linking, session-killing, 4-stage pipeline,
-- ephemeral alerts, and month-wise report views.
-- ============================================================
CREATE DATABASE IF NOT EXISTS starkidz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE starkidz;

-- ---------- Departments & Staff ----------
CREATE TABLE IF NOT EXISTS departments (
  id   INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(60) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(40) UNIQUE NOT NULL,           -- exact: 'SUPERVISOR:3','SUPERVISOR-4','MASTER'
  full_name     VARCHAR(80) NOT NULL,
  password_hash VARCHAR(100) NOT NULL,                 -- bcrypt
  department_id INT,
  role          ENUM('Sales Staff','Production G.M','Supervisor','System Master') NOT NULL,
  is_master     TINYINT(1) NOT NULL DEFAULT 0,
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (department_id) REFERENCES departments(id)
);

-- ---------- Session-killing support (one active session per user, except master) ----------
CREATE TABLE IF NOT EXISTS sessions (
  id          CHAR(36) PRIMARY KEY,
  user_id     INT NOT NULL,
  token_jti   CHAR(36) NOT NULL,                       -- JWT id; old jti invalidated on new login
  device_info VARCHAR(255),
  socket_id   VARCHAR(64),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen   DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_sessions_user (user_id),
  INDEX idx_sessions_jti  (token_jti),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ---------- Orders + out-of-stock link + sequential pipeline ----------
-- NOTE: combined category 'PU PVC STUCKEN' is intentionally NOT a valid value (Module 2.3 scrub).
CREATE TABLE IF NOT EXISTS orders (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  order_no        VARCHAR(20) UNIQUE NOT NULL,
  customer_name   VARCHAR(120) NOT NULL,
  article_code    VARCHAR(40)  NOT NULL,
  article_name    VARCHAR(120) NOT NULL,
  category        ENUM('PU','PVC','Stuckon') NOT NULL,
  quantity        INT NOT NULL,
  order_date      DATE NOT NULL,
  delivery_date   DATE NOT NULL,                       -- committed distributor timeline
  priority        VARCHAR(10) DEFAULT 'Medium',
  is_out_of_stock TINYINT(1) NOT NULL DEFAULT 0,       -- triggers production cross-link
  created_by      INT,
  current_stage   ENUM('UPPER','MOULDING','PACKING','DISPATCH'),
  closed          TINYINT(1) DEFAULT 0,
  created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- One row per stage per order = the live 4-stage matrix
CREATE TABLE IF NOT EXISTS order_stages (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT NOT NULL,
  stage      ENUM('UPPER','MOULDING','PACKING','DISPATCH') NOT NULL,
  state      ENUM('Pending','In Progress','Completed') NOT NULL DEFAULT 'Pending',
  produced   INT DEFAULT 0,
  updated_by INT,
  updated_at DATETIME,
  UNIQUE KEY uq_order_stage (order_id, stage),
  FOREIGN KEY (order_id)  REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (updated_by) REFERENCES users(id)
);

-- Raw material readiness (alerts must show modification date)
CREATE TABLE IF NOT EXISTS raw_material_status (
  order_id        INT PRIMARY KEY,
  required_qty    INT, available_qty INT, pending_qty INT,
  expected_arrival DATE,
  modified_by     INT,
  modified_at     DATETIME,                            -- "Raw Material Modification Date"
  FOREIGN KEY (order_id)   REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (modified_by) REFERENCES users(id)
);

-- ---------- Ephemeral alerts (5-min lifespan; app dismiss + DB safety sweep) ----------
CREATE TABLE IF NOT EXISTS alerts (
  id          CHAR(36) PRIMARY KEY,
  type        VARCHAR(30),
  title       VARCHAR(140),
  body        TEXT,
  order_id    INT,
  target_user INT,
  target_dept INT,
  dismissed   TINYINT(1) DEFAULT 0,
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at  DATETIME,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- ---------- Reporting views (Module 3) ----------
CREATE OR REPLACE VIEW v_month_pending AS
SELECT DATE_FORMAT(delivery_date,'%Y-%m') AS month, COUNT(*) AS pending_orders
FROM orders WHERE closed = 0 GROUP BY 1;

CREATE OR REPLACE VIEW v_month_dispatch AS
SELECT DATE_FORMAT(delivery_date,'%Y-%m') AS month, COUNT(*) AS dispatched_orders
FROM orders WHERE closed = 1 GROUP BY 1;

-- Next-month roll-over forecast based on committed delivery dates
CREATE OR REPLACE VIEW v_next_month_pendency AS
SELECT * FROM orders
WHERE closed = 0
  AND delivery_date >= DATE_FORMAT(CURDATE() + INTERVAL 1 MONTH, '%Y-%m-01')
  AND delivery_date <  DATE_FORMAT(CURDATE() + INTERVAL 2 MONTH, '%Y-%m-01');
