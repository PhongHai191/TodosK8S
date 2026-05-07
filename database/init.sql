-- =========================
-- EXTENSIONS
-- =========================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================
-- USERS TABLE
-- =========================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,

    fullname TEXT,
    email TEXT UNIQUE,
    phone TEXT,

    avatar TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================
-- TODOS TABLE
-- =========================
CREATE TABLE IF NOT EXISTS todos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    text TEXT NOT NULL,
    user_id UUID NOT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_user
        FOREIGN KEY(user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

-- =========================
-- INDEXES (IMPORTANT)
-- =========================

-- Query todos theo user nhanh hơn
CREATE INDEX IF NOT EXISTS idx_todos_user_id
ON todos(user_id);

-- Search username nhanh hơn
CREATE INDEX IF NOT EXISTS idx_users_username
ON users(username);

-- =========================
-- TRIGGER: AUTO UPDATE updated_at
-- =========================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = CURRENT_TIMESTAMP;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trigger_update_users
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();
