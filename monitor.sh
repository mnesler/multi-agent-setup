#!/bin/bash
# Standalone monitoring dashboard for multi-agent system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${AGENT_DB_DIR:-/tmp/multi-agent-system}"
DB_PATH="${DB_DIR}/agents.db"

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found at $DB_PATH"
    echo "Run ./db-init.sh first"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear_screen() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║               Multi-Agent System Monitoring Dashboard                      ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Database: $DB_PATH"
    echo "Updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
}

show_summary() {
    echo -e "${BOLD}${GREEN}=== System Summary ===${NC}"

    local total_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks;")
    local pending_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='pending';")
    local active_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='in_progress';")
    local completed_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='complete';")
    local failed_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='failed';")

    local total_agents=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agents;")
    local active_agents=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agents WHERE status!='offline';")
    local busy_agents=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agents WHERE status='busy';")

    local unread_messages=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM messages WHERE consumed=0;")

    echo -e "  Tasks:    Total: ${BOLD}$total_tasks${NC} | Pending: ${YELLOW}$pending_tasks${NC} | Active: ${BLUE}$active_tasks${NC} | Complete: ${GREEN}$completed_tasks${NC} | Failed: ${RED}$failed_tasks${NC}"
    echo -e "  Agents:   Total: ${BOLD}$total_agents${NC} | Active: ${GREEN}$active_agents${NC} | Busy: ${BLUE}$busy_agents${NC}"
    echo -e "  Messages: Unread: ${YELLOW}$unread_messages${NC}"
    echo
}

show_agents() {
    echo -e "${BOLD}${BLUE}=== Agent Status ===${NC}"

    sqlite3 -box "$DB_PATH" <<EOF
SELECT
    agent_id as "Agent ID",
    agent_type as "Type",
    status as "Status",
    total_tasks_completed as "Completed",
    total_tasks_failed as "Failed",
    current_task_id as "Current Task",
    CASE
        WHEN (julianday('now') - julianday(last_heartbeat)) * 86400 < 30 THEN 'Healthy'
        WHEN (julianday('now') - julianday(last_heartbeat)) * 86400 < 60 THEN 'Warning'
        ELSE 'Stale'
    END as "Health",
    strftime('%H:%M:%S', last_heartbeat, 'localtime') as "Last Heartbeat"
FROM agents
ORDER BY agent_id;
EOF
    echo
}

show_pending_tasks() {
    echo -e "${BOLD}${YELLOW}=== Pending Tasks ===${NC}"

    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='pending';")

    if [ "$count" -eq 0 ]; then
        echo "  No pending tasks"
    else
        sqlite3 -box "$DB_PATH" <<EOF
SELECT
    substr(id, 1, 20) as "Task ID",
    task_type as "Type",
    COALESCE(assigned_to, 'unassigned') as "Assigned To",
    priority as "Pri",
    strftime('%H:%M:%S', created_at, 'localtime') as "Created"
FROM tasks
WHERE status = 'pending'
ORDER BY priority DESC, created_at ASC
LIMIT 10;
EOF
    fi
    echo
}

show_active_tasks() {
    echo -e "${BOLD}${BLUE}=== Active Tasks ===${NC}"

    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='in_progress';")

    if [ "$count" -eq 0 ]; then
        echo "  No active tasks"
    else
        sqlite3 -box "$DB_PATH" <<EOF
SELECT
    substr(id, 1, 20) as "Task ID",
    task_type as "Type",
    assigned_to as "Agent",
    strftime('%H:%M:%S', started_at, 'localtime') as "Started",
    CAST((julianday('now') - julianday(started_at)) * 1440 AS INTEGER) || 'm' as "Duration"
FROM tasks
WHERE status = 'in_progress'
ORDER BY started_at ASC;
EOF
    fi
    echo
}

show_recent_completions() {
    echo -e "${BOLD}${GREEN}=== Recent Completions ===${NC}"

    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='complete' AND datetime(completed_at) > datetime('now', '-1 hour');")

    if [ "$count" -eq 0 ]; then
        echo "  No recent completions (last hour)"
    else
        sqlite3 -box "$DB_PATH" <<EOF
SELECT
    substr(id, 1, 20) as "Task ID",
    task_type as "Type",
    assigned_to as "Agent",
    strftime('%H:%M:%S', completed_at, 'localtime') as "Completed"
FROM tasks
WHERE status = 'complete'
  AND datetime(completed_at) > datetime('now', '-1 hour')
ORDER BY completed_at DESC
LIMIT 5;
EOF
    fi
    echo
}

show_failures() {
    echo -e "${BOLD}${RED}=== Recent Failures ===${NC}"

    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='failed' AND datetime(completed_at) > datetime('now', '-1 hour');")

    if [ "$count" -eq 0 ]; then
        echo "  No recent failures (last hour)"
    else
        sqlite3 -box "$DB_PATH" <<EOF
SELECT
    substr(id, 1, 20) as "Task ID",
    task_type as "Type",
    assigned_to as "Agent",
    substr(error_message, 1, 30) as "Error",
    retries as "Retries"
FROM tasks
WHERE status = 'failed'
  AND datetime(completed_at) > datetime('now', '-1 hour')
ORDER BY completed_at DESC
LIMIT 5;
EOF
    fi
    echo
}

show_messages() {
    echo -e "${BOLD}${CYAN}=== Recent Messages ===${NC}"

    local count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM messages WHERE consumed=0;")

    if [ "$count" -eq 0 ]; then
        echo "  No unread messages"
    else
        sqlite3 -box "$DB_PATH" <<EOF
SELECT
    from_agent as "From",
    COALESCE(to_agent, 'broadcast') as "To",
    topic as "Topic",
    substr(json_extract(payload, '$'), 1, 40) as "Payload",
    strftime('%H:%M:%S', created_at, 'localtime') as "Time"
FROM messages
WHERE consumed = 0
ORDER BY created_at DESC
LIMIT 10;
EOF
    fi
    echo
}

show_performance() {
    echo -e "${BOLD}${GREEN}=== Agent Performance ===${NC}"

    sqlite3 -box "$DB_PATH" <<EOF
SELECT
    agent_type as "Type",
    COUNT(DISTINCT agent_id) as "Count",
    SUM(total_tasks_completed) as "Total Completed",
    SUM(total_tasks_failed) as "Total Failed",
    PRINTF('%.1f%%',
        CAST(SUM(total_tasks_completed) AS REAL) * 100.0 /
        NULLIF(SUM(total_tasks_completed) + SUM(total_tasks_failed), 0)
    ) as "Success Rate"
FROM agents
GROUP BY agent_type
ORDER BY agent_type;
EOF
    echo
}

# Main display function
display_dashboard() {
    clear_screen
    show_summary
    show_agents
    show_pending_tasks
    show_active_tasks
    show_recent_completions
    show_failures
    show_messages
    show_performance

    echo -e "${CYAN}Press Ctrl+C to exit, or wait for auto-refresh...${NC}"
}

# Interactive mode vs one-shot
if [ "$1" == "--watch" ] || [ "$1" == "-w" ]; then
    # Watch mode - continuous updates
    INTERVAL="${2:-5}"
    echo "Starting monitoring in watch mode (refresh every ${INTERVAL}s)..."
    sleep 1

    while true; do
        display_dashboard
        sleep "$INTERVAL"
    done
else
    # One-shot display
    display_dashboard
fi
