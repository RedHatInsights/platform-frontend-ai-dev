CREATE EXTENSION IF NOT EXISTS vector;

DO $$ BEGIN
    CREATE TYPE task_status AS ENUM (
        'in_progress', 'pr_open', 'pr_changes', 'paused', 'done'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS tasks (
    id              SERIAL PRIMARY KEY,
    jira_key        TEXT NOT NULL UNIQUE,
    status          task_status NOT NULL DEFAULT 'in_progress',
    repo            TEXT,
    branch          TEXT,
    pr_number       INTEGER,
    pr_url          TEXT,
    title           TEXT,
    summary         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_addressed  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paused_reason   TEXT,
    metadata        JSONB DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS memories (
    id              SERIAL PRIMARY KEY,
    category        TEXT NOT NULL,
    repo            TEXT,
    jira_key        TEXT,
    title           TEXT NOT NULL,
    content         TEXT NOT NULL,
    tags            TEXT[] DEFAULT '{}',
    embedding       vector(384) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata        JSONB DEFAULT '{}'
);

-- Add title and summary columns if they don't exist (for existing databases)
DO $$ BEGIN
    ALTER TABLE tasks ADD COLUMN IF NOT EXISTS title TEXT;
    ALTER TABLE tasks ADD COLUMN IF NOT EXISTS summary TEXT;
EXCEPTION
    WHEN duplicate_column THEN NULL;
END $$;

-- Add tags column if it doesn't exist (for existing databases)
DO $$ BEGIN
    ALTER TABLE memories ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';
EXCEPTION
    WHEN duplicate_column THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS bot_status (
    id              INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    state           TEXT NOT NULL DEFAULT 'idle',
    message         TEXT NOT NULL DEFAULT '',
    jira_key        TEXT,
    repo            TEXT,
    cycle_start     TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO bot_status (id) VALUES (1) ON CONFLICT DO NOTHING;

-- Only create index if table has enough rows (ivfflat needs data)
-- On first startup with empty table, queries fall back to sequential scan
-- Re-run this after seeding data:
-- CREATE INDEX IF NOT EXISTS idx_memories_embedding
--   ON memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 20);
