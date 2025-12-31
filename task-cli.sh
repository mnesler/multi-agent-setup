#!/bin/bash
# CLI tool for task management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/task-utils.sh"

show_help() {
    cat <<EOF
Task Management CLI

Usage: task-cli.sh <command> [options]

Commands:
    add <type> <payload-json> [agent] [priority]
        Add a new task to the queue
        Example: task-cli.sh add "code_review" '{"file":"main.py"}' researcher 8

    list [status]
        List all tasks (optionally filter by status)
        Example: task-cli.sh list pending

    status <task-id>
        Get detailed status of a specific task
        Example: task-cli.sh status task-1234567890-5678

    complete <task-id> <result-json>
        Mark a task as complete with results
        Example: task-cli.sh complete task-123 '{"status":"ok"}'

    fail <task-id> <error-message>
        Mark a task as failed
        Example: task-cli.sh fail task-123 "Compilation error"

    send <from> <to> <topic> <payload-json>
        Send message between agents
        Example: task-cli.sh send agent1 agent2 status '{"ready":true}'

    receive <agent-id> [topic]
        Receive messages for an agent
        Example: task-cli.sh receive agent1 status

    cleanup [days]
        Clean up old completed/failed tasks
        Example: task-cli.sh cleanup 7

    stats
        Show system statistics

    help
        Show this help message

EOF
}

show_stats() {
    echo "=== Multi-Agent System Statistics ==="
    echo
    echo "Tasks:"
    sqlite3 "$AGENT_DB_PATH" <<EOF
SELECT
    '  Pending: ' || COUNT(*) FROM tasks WHERE status = 'pending'
    UNION ALL SELECT
    '  In Progress: ' || COUNT(*) FROM tasks WHERE status = 'in_progress'
    UNION ALL SELECT
    '  Completed: ' || COUNT(*) FROM tasks WHERE status = 'complete'
    UNION ALL SELECT
    '  Failed: ' || COUNT(*) FROM tasks WHERE status = 'failed';
EOF

    echo
    echo "Agents:"
    sqlite3 "$AGENT_DB_PATH" <<EOF
SELECT
    '  Total: ' || COUNT(*) FROM agents
    UNION ALL SELECT
    '  Active: ' || COUNT(*) FROM agents WHERE status != 'offline'
    UNION ALL SELECT
    '  Idle: ' || COUNT(*) FROM agents WHERE status = 'idle'
    UNION ALL SELECT
    '  Busy: ' || COUNT(*) FROM agents WHERE status = 'busy';
EOF

    echo
    echo "Messages:"
    sqlite3 "$AGENT_DB_PATH" "SELECT '  Unread: ' || COUNT(*) FROM messages WHERE consumed = 0;"

    echo
    echo "Agent Performance:"
    sqlite3 -box "$AGENT_DB_PATH" <<EOF
SELECT
    agent_id as Agent,
    total_tasks_completed as Completed,
    total_tasks_failed as Failed,
    status as Status,
    datetime(last_heartbeat, 'localtime') as "Last Heartbeat"
FROM agents
ORDER BY total_tasks_completed DESC;
EOF
}

# Main command dispatcher
case "$1" in
    add)
        if [ $# -lt 3 ]; then
            echo "Error: Missing arguments"
            echo "Usage: task-cli.sh add <type> <payload-json> [agent] [priority]"
            exit 1
        fi
        task_id=$(enqueue_task "$2" "$3" "${4:-}" "${5:-5}")
        echo "Task created: $task_id"
        ;;

    list)
        status="${2:-}"
        if [ -n "$status" ]; then
            echo "=== Tasks with status: $status ==="
            sqlite3 -json "$AGENT_DB_PATH" "SELECT * FROM tasks WHERE status = '$status' ORDER BY priority DESC, created_at ASC;" | jq -r '.[] | "\(.id) | \(.task_type) | \(.assigned_to // "unassigned") | Pri:\(.priority) | \(.created_at)"'
        else
            echo "=== All Tasks ==="
            sqlite3 -box "$AGENT_DB_PATH" "SELECT id, status, task_type, assigned_to, priority, created_at FROM tasks ORDER BY created_at DESC LIMIT 20;"
        fi
        ;;

    status)
        if [ $# -lt 2 ]; then
            echo "Error: Missing task ID"
            exit 1
        fi
        get_task_status "$2" | jq '.'
        ;;

    complete)
        if [ $# -lt 3 ]; then
            echo "Error: Missing arguments"
            echo "Usage: task-cli.sh complete <task-id> <result-json>"
            exit 1
        fi
        complete_task "$2" "$3"
        ;;

    fail)
        if [ $# -lt 3 ]; then
            echo "Error: Missing arguments"
            echo "Usage: task-cli.sh fail <task-id> <error-message>"
            exit 1
        fi
        fail_task "$2" "$3"
        ;;

    send)
        if [ $# -lt 5 ]; then
            echo "Error: Missing arguments"
            echo "Usage: task-cli.sh send <from> <to> <topic> <payload-json>"
            exit 1
        fi
        send_message "$2" "$3" "$4" "$5"
        ;;

    receive)
        if [ $# -lt 2 ]; then
            echo "Error: Missing agent ID"
            exit 1
        fi
        receive_messages "$2" "${3:-}" | jq -r '.[] | "[\(.created_at)] \(.from_agent) -> \(.topic): \(.payload | @json)"'
        ;;

    cleanup)
        cleanup_old_tasks "${2:-7}"
        ;;

    stats)
        show_stats
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        echo "Error: Unknown command '$1'"
        echo
        show_help
        exit 1
        ;;
esac
