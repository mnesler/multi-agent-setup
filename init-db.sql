-- Multi-Agent System Database Schema
-- SQLite database for task queue and agent coordination

-- Task queue table
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    assigned_to TEXT,
    status TEXT CHECK(status IN ('pending', 'in_progress', 'complete', 'failed')) DEFAULT 'pending',
    priority INTEGER DEFAULT 5,
    task_type TEXT,
    payload JSON NOT NULL,
    result JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,
    retries INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    error_message TEXT
);

-- Index for efficient task assignment queries
CREATE INDEX IF NOT EXISTS idx_tasks_status_priority
    ON tasks(status, priority DESC, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_tasks_assigned
    ON tasks(assigned_to, status);

-- Inter-agent message queue
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_agent TEXT NOT NULL,
    to_agent TEXT,  -- NULL means broadcast to all agents
    topic TEXT,
    payload JSON NOT NULL,
    consumed INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Index for message retrieval
CREATE INDEX IF NOT EXISTS idx_messages_to_consumed
    ON messages(to_agent, consumed, created_at);

CREATE INDEX IF NOT EXISTS idx_messages_topic
    ON messages(topic, consumed);

-- Agent registry for discovery and health monitoring
CREATE TABLE IF NOT EXISTS agents (
    agent_id TEXT PRIMARY KEY,
    agent_type TEXT,
    capabilities JSON,
    status TEXT CHECK(status IN ('idle', 'busy', 'offline')) DEFAULT 'idle',
    current_task_id TEXT,
    last_heartbeat DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_tasks_completed INTEGER DEFAULT 0,
    total_tasks_failed INTEGER DEFAULT 0,
    metadata JSON
);

-- Task assignment history for analytics
CREATE TABLE IF NOT EXISTS task_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    action TEXT,  -- 'assigned', 'started', 'completed', 'failed', 'retried'
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    details JSON
);

-- System configuration
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Initial configuration
INSERT OR IGNORE INTO config (key, value) VALUES
    ('system_version', '1.0.0'),
    ('max_task_retries', '3'),
    ('agent_heartbeat_timeout_seconds', '30'),
    ('task_cleanup_days', '7');

-- Views for convenient querying

-- Active tasks view
CREATE VIEW IF NOT EXISTS v_active_tasks AS
SELECT
    t.id,
    t.assigned_to,
    t.status,
    t.priority,
    t.task_type,
    t.payload,
    t.created_at,
    t.started_at,
    julianday('now') - julianday(t.created_at) as age_days,
    a.agent_id,
    a.status as agent_status
FROM tasks t
LEFT JOIN agents a ON t.assigned_to = a.agent_id
WHERE t.status IN ('pending', 'in_progress')
ORDER BY t.priority DESC, t.created_at ASC;

-- Agent health view
CREATE VIEW IF NOT EXISTS v_agent_health AS
SELECT
    agent_id,
    agent_type,
    status,
    current_task_id,
    total_tasks_completed,
    total_tasks_failed,
    CASE
        WHEN (julianday('now') - julianday(last_heartbeat)) * 86400 > 30
        THEN 'stale'
        ELSE 'healthy'
    END as health_status,
    julianday('now') - julianday(last_heartbeat) as seconds_since_heartbeat,
    last_heartbeat
FROM agents;

-- Unread messages view
CREATE VIEW IF NOT EXISTS v_unread_messages AS
SELECT
    id,
    from_agent,
    to_agent,
    topic,
    payload,
    created_at
FROM messages
WHERE consumed = 0
ORDER BY created_at ASC;
