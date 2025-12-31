#!/bin/bash
# Task management utilities for multi-agent system

# Load environment
if [ -f "/tmp/multi-agent-system/.env" ]; then
    source "/tmp/multi-agent-system/.env"
fi

AGENT_DB_PATH="${AGENT_DB_PATH:-/tmp/multi-agent-system/agents.db}"

# Ensure database exists
if [ ! -f "$AGENT_DB_PATH" ]; then
    echo "Error: Database not found at $AGENT_DB_PATH"
    echo "Run ./db-init.sh first"
    exit 1
fi

# Generate unique task ID
generate_task_id() {
    echo "task-$(date +%s)-$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
}

# Enqueue a new task
# Usage: enqueue_task <task_type> <payload_json> [assigned_to] [priority]
enqueue_task() {
    local task_type="$1"
    local payload="$2"
    local assigned_to="${3:-}"
    local priority="${4:-5}"
    local task_id=$(generate_task_id)

    # Validate JSON payload
    if ! echo "$payload" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON payload"
        return 1
    fi

    sqlite3 "$AGENT_DB_PATH" <<EOF
INSERT INTO tasks (id, task_type, payload, assigned_to, priority, status)
VALUES (
    '$task_id',
    '$task_type',
    json('$payload'),
    $([ -n "$assigned_to" ] && echo "'$assigned_to'" || echo "NULL"),
    $priority,
    'pending'
);
EOF

    if [ $? -eq 0 ]; then
        echo "$task_id"
        return 0
    else
        echo "Error: Failed to enqueue task"
        return 1
    fi
}

# Dequeue next available task for an agent
# Usage: dequeue_task <agent_id>
dequeue_task() {
    local agent_id="$1"

    # Start transaction and claim task
    sqlite3 -json "$AGENT_DB_PATH" <<EOF
BEGIN TRANSACTION;

-- Find highest priority pending task for this agent or unassigned
SELECT json_object(
    'id', id,
    'task_type', task_type,
    'payload', json(payload),
    'priority', priority,
    'created_at', created_at
) as task
FROM tasks
WHERE status = 'pending'
  AND (assigned_to = '$agent_id' OR assigned_to IS NULL)
ORDER BY priority DESC, created_at ASC
LIMIT 1;

-- Update task status
UPDATE tasks
SET status = 'in_progress',
    assigned_to = '$agent_id',
    started_at = datetime('now')
WHERE id = (
    SELECT id FROM tasks
    WHERE status = 'pending'
      AND (assigned_to = '$agent_id' OR assigned_to IS NULL)
    ORDER BY priority DESC, created_at ASC
    LIMIT 1
);

-- Log to history
INSERT INTO task_history (task_id, agent_id, action)
SELECT id, '$agent_id', 'started'
FROM tasks
WHERE assigned_to = '$agent_id' AND status = 'in_progress'
ORDER BY started_at DESC
LIMIT 1;

COMMIT;
EOF
}

# Complete a task with result
# Usage: complete_task <task_id> <result_json>
complete_task() {
    local task_id="$1"
    local result="$2"

    # Validate JSON result
    if ! echo "$result" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON result"
        return 1
    fi

    sqlite3 "$AGENT_DB_PATH" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'complete',
    result = json('$result'),
    completed_at = datetime('now')
WHERE id = '$task_id';

INSERT INTO task_history (task_id, agent_id, action, details)
SELECT '$task_id', assigned_to, 'completed', json('$result')
FROM tasks
WHERE id = '$task_id';

-- Update agent stats
UPDATE agents
SET total_tasks_completed = total_tasks_completed + 1,
    status = 'idle',
    current_task_id = NULL
WHERE agent_id = (SELECT assigned_to FROM tasks WHERE id = '$task_id');

COMMIT;
EOF

    echo "Task $task_id marked as complete"
}

# Fail a task with error message
# Usage: fail_task <task_id> <error_message>
fail_task() {
    local task_id="$1"
    local error_msg="$2"

    sqlite3 "$AGENT_DB_PATH" <<EOF
BEGIN TRANSACTION;

UPDATE tasks
SET status = 'failed',
    error_message = '$error_msg',
    completed_at = datetime('now'),
    retries = retries + 1
WHERE id = '$task_id';

INSERT INTO task_history (task_id, agent_id, action, details)
SELECT '$task_id', assigned_to, 'failed', json_object('error', '$error_msg')
FROM tasks
WHERE id = '$task_id';

-- Update agent stats
UPDATE agents
SET total_tasks_failed = total_tasks_failed + 1,
    status = 'idle',
    current_task_id = NULL
WHERE agent_id = (SELECT assigned_to FROM tasks WHERE id = '$task_id');

COMMIT;
EOF

    # Check if should retry
    local retries=$(sqlite3 "$AGENT_DB_PATH" "SELECT retries FROM tasks WHERE id = '$task_id';")
    local max_retries=$(sqlite3 "$AGENT_DB_PATH" "SELECT max_retries FROM tasks WHERE id = '$task_id';")

    if [ "$retries" -lt "$max_retries" ]; then
        echo "Task $task_id failed (retry $retries/$max_retries), will retry"
        sqlite3 "$AGENT_DB_PATH" "UPDATE tasks SET status = 'pending' WHERE id = '$task_id';"
    else
        echo "Task $task_id failed permanently after $retries retries"
    fi
}

# Get task status
# Usage: get_task_status <task_id>
get_task_status() {
    local task_id="$1"

    sqlite3 -json "$AGENT_DB_PATH" <<EOF
SELECT json_object(
    'id', id,
    'status', status,
    'task_type', task_type,
    'assigned_to', assigned_to,
    'payload', json(payload),
    'result', json(result),
    'created_at', created_at,
    'started_at', started_at,
    'completed_at', completed_at,
    'retries', retries,
    'error_message', error_message
) as task_info
FROM tasks
WHERE id = '$task_id';
EOF
}

# List all pending tasks
list_pending_tasks() {
    sqlite3 -json "$AGENT_DB_PATH" <<EOF
SELECT json_object(
    'id', id,
    'task_type', task_type,
    'assigned_to', assigned_to,
    'priority', priority,
    'created_at', created_at
) as task
FROM tasks
WHERE status = 'pending'
ORDER BY priority DESC, created_at ASC;
EOF
}

# List tasks for specific agent
# Usage: list_agent_tasks <agent_id> [status]
list_agent_tasks() {
    local agent_id="$1"
    local status="${2:-}"

    local status_filter=""
    if [ -n "$status" ]; then
        status_filter="AND status = '$status'"
    fi

    sqlite3 -json "$AGENT_DB_PATH" <<EOF
SELECT json_object(
    'id', id,
    'status', status,
    'task_type', task_type,
    'priority', priority,
    'created_at', created_at,
    'started_at', started_at
) as task
FROM tasks
WHERE assigned_to = '$agent_id' $status_filter
ORDER BY created_at DESC;
EOF
}

# Send message between agents
# Usage: send_message <from_agent> <to_agent> <topic> <payload_json>
send_message() {
    local from_agent="$1"
    local to_agent="$2"  # Use "broadcast" for all agents
    local topic="$3"
    local payload="$4"

    # Validate JSON payload
    if ! echo "$payload" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON payload"
        return 1
    fi

    local to_agent_value="NULL"
    if [ "$to_agent" != "broadcast" ]; then
        to_agent_value="'$to_agent'"
    fi

    sqlite3 "$AGENT_DB_PATH" <<EOF
INSERT INTO messages (from_agent, to_agent, topic, payload)
VALUES (
    '$from_agent',
    $to_agent_value,
    '$topic',
    json('$payload')
);
EOF

    echo "Message sent from $from_agent to ${to_agent:-all} on topic $topic"
}

# Receive messages for an agent
# Usage: receive_messages <agent_id> [topic]
receive_messages() {
    local agent_id="$1"
    local topic="${2:-}"

    local topic_filter=""
    if [ -n "$topic" ]; then
        topic_filter="AND topic = '$topic'"
    fi

    sqlite3 -json "$AGENT_DB_PATH" <<EOF
BEGIN TRANSACTION;

-- Get unread messages
SELECT json_object(
    'id', id,
    'from_agent', from_agent,
    'topic', topic,
    'payload', json(payload),
    'created_at', created_at
) as message
FROM messages
WHERE consumed = 0
  AND (to_agent = '$agent_id' OR to_agent IS NULL)
  $topic_filter
ORDER BY created_at ASC;

-- Mark as consumed
UPDATE messages
SET consumed = 1
WHERE consumed = 0
  AND (to_agent = '$agent_id' OR to_agent IS NULL)
  $topic_filter;

COMMIT;
EOF
}

# Clean up old completed/failed tasks
# Usage: cleanup_old_tasks [days]
cleanup_old_tasks() {
    local days="${1:-7}"

    sqlite3 "$AGENT_DB_PATH" <<EOF
DELETE FROM tasks
WHERE status IN ('complete', 'failed')
  AND julianday('now') - julianday(completed_at) > $days;

DELETE FROM messages
WHERE consumed = 1
  AND julianday('now') - julianday(created_at) > $days;
EOF

    echo "Cleaned up tasks/messages older than $days days"
}

# Export functions for use in other scripts
export -f enqueue_task
export -f dequeue_task
export -f complete_task
export -f fail_task
export -f get_task_status
export -f list_pending_tasks
export -f list_agent_tasks
export -f send_message
export -f receive_messages
export -f cleanup_old_tasks
