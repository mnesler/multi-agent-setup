#!/bin/bash
# Agent wrapper script for Claude Code instances
# This script runs in each tmux pane and manages a Claude Code agent

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/task-utils.sh"

# Agent configuration
AGENT_ID="${AGENT_ID:-agent-$(hostname)-$$}"
AGENT_TYPE="${AGENT_TYPE:-general}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
LOG_DIR="${AGENT_LOG_DIR:-/tmp/multi-agent-system/logs}"
STATE_DIR="${AGENT_STATE_DIR:-/tmp/multi-agent-system/state}"

# Create directories
mkdir -p "$LOG_DIR" "$STATE_DIR"

# Log files
AGENT_LOG="$LOG_DIR/${AGENT_ID}.log"
TASK_LOG="$LOG_DIR/${AGENT_ID}-tasks.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$AGENT_LOG"
}

log_info() {
    log "${GREEN}INFO${NC}" "$@"
}

log_warn() {
    log "${YELLOW}WARN${NC}" "$@"
}

log_error() {
    log "${RED}ERROR${NC}" "$@"
}

# Register agent in database
register_agent() {
    log_info "Registering agent: $AGENT_ID (type: $AGENT_TYPE)"

    local capabilities='{"poll_interval": '$POLL_INTERVAL', "tools": ["claude-code"]}'

    sqlite3 "$AGENT_DB_PATH" <<EOF
INSERT OR REPLACE INTO agents (agent_id, agent_type, capabilities, status, last_heartbeat)
VALUES (
    '$AGENT_ID',
    '$AGENT_TYPE',
    json('$capabilities'),
    'idle',
    datetime('now')
);
EOF

    log_info "Agent registered successfully"
}

# Update heartbeat
heartbeat() {
    sqlite3 "$AGENT_DB_PATH" <<EOF
UPDATE agents
SET last_heartbeat = datetime('now')
WHERE agent_id = '$AGENT_ID';
EOF
}

# Update agent status
update_status() {
    local status="$1"
    local task_id="${2:-NULL}"

    local task_value="NULL"
    if [ "$task_id" != "NULL" ]; then
        task_value="'$task_id'"
    fi

    sqlite3 "$AGENT_DB_PATH" <<EOF
UPDATE agents
SET status = '$status',
    current_task_id = $task_value
WHERE agent_id = '$AGENT_ID';
EOF
}

# Process a task with Claude Code
process_task() {
    local task_json="$1"

    # Parse task details
    local task_id=$(echo "$task_json" | jq -r '.[0].id')
    local task_type=$(echo "$task_json" | jq -r '.[0].task_type')
    local payload=$(echo "$task_json" | jq -r '.[0].payload')

    # Check if we got a task
    if [ "$task_id" == "null" ] || [ -z "$task_id" ]; then
        return 1
    fi

    log_info "${BLUE}Processing task: $task_id (type: $task_type)${NC}"
    echo "$task_json" | jq '.' >> "$TASK_LOG"

    # Update status
    update_status "busy" "$task_id"

    # Create task-specific workspace
    local task_workspace="$STATE_DIR/${task_id}"
    mkdir -p "$task_workspace"

    # Write task details to workspace
    echo "$payload" > "$task_workspace/input.json"

    # Build Claude Code prompt based on task type
    local prompt=$(build_prompt "$task_type" "$payload")

    # Execute task
    local result
    local exit_code=0

    log_info "Executing Claude Code with prompt..."

    # Run Claude Code (adjust based on your setup)
    # Option 1: Non-interactive mode
    if command -v claude &> /dev/null; then
        # Use claude CLI if available
        result=$(execute_claude_task "$task_workspace" "$prompt" "$task_type") || exit_code=$?
    else
        # Fallback: manual processing
        log_warn "Claude Code not found, using manual processing"
        result=$(manual_process_task "$task_type" "$payload") || exit_code=$?
    fi

    # Save result
    echo "$result" > "$task_workspace/result.json"

    # Update task status
    if [ $exit_code -eq 0 ]; then
        log_info "${GREEN}Task completed successfully${NC}"
        complete_task "$task_id" "$result"
    else
        log_error "Task failed with exit code $exit_code"
        fail_task "$task_id" "$result"
    fi

    # Update agent status back to idle
    update_status "idle"

    return $exit_code
}

# Build prompt for Claude Code based on task type
build_prompt() {
    local task_type="$1"
    local payload="$2"

    case "$task_type" in
        "code_review")
            local file=$(echo "$payload" | jq -r '.file')
            echo "Review the code in $file and provide feedback on code quality, potential bugs, and improvements."
            ;;

        "implement_feature")
            local spec=$(echo "$payload" | jq -r '.specification')
            echo "Implement the following feature: $spec"
            ;;

        "fix_bug")
            local description=$(echo "$payload" | jq -r '.description')
            local file=$(echo "$payload" | jq -r '.file // empty')
            if [ -n "$file" ]; then
                echo "Fix the following bug in $file: $description"
            else
                echo "Fix the following bug: $description"
            fi
            ;;

        "analyze")
            local target=$(echo "$payload" | jq -r '.target')
            local question=$(echo "$payload" | jq -r '.question // empty')
            if [ -n "$question" ]; then
                echo "Analyze $target and answer: $question"
            else
                echo "Analyze $target and provide insights"
            fi
            ;;

        "test")
            local target=$(echo "$payload" | jq -r '.target')
            echo "Write tests for $target"
            ;;

        "custom")
            echo "$payload" | jq -r '.prompt'
            ;;

        *)
            echo "Process the following task: $payload"
            ;;
    esac
}

# Execute task with Claude Code
execute_claude_task() {
    local workspace="$1"
    local prompt="$2"
    local task_type="$3"

    cd "$workspace" 2>/dev/null || cd /tmp

    # Create a temporary file for the prompt
    local prompt_file="$workspace/prompt.txt"
    echo "$prompt" > "$prompt_file"

    # Execute Claude in non-interactive mode if supported
    # Note: This is a placeholder - adjust based on actual Claude Code CLI
    local output
    local status=0

    # Try to run claude with the prompt
    if claude -p "$prompt" &> "$workspace/claude-output.txt"; then
        output=$(cat "$workspace/claude-output.txt")
        status=0
    else
        output=$(cat "$workspace/claude-output.txt")
        status=1
    fi

    # Format result as JSON
    jq -n \
        --arg status "$status" \
        --arg output "$output" \
        --arg task_type "$task_type" \
        '{
            status: (if $status == "0" then "success" else "error" end),
            task_type: $task_type,
            output: $output,
            timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }'

    return $status
}

# Manual task processing (fallback when Claude Code not available)
manual_process_task() {
    local task_type="$1"
    local payload="$2"

    log_warn "Manual processing for task type: $task_type"

    # Return a success result
    jq -n \
        --arg task_type "$task_type" \
        --argjson payload "$payload" \
        '{
            status: "manual_processing_required",
            task_type: $task_type,
            payload: $payload,
            message: "This task requires manual processing with Claude Code",
            timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }'
}

# Cleanup on exit
cleanup() {
    log_info "Shutting down agent $AGENT_ID"
    update_status "offline"
    exit 0
}

trap cleanup EXIT INT TERM

# Main agent loop
main() {
    log_info "========================================="
    log_info "Starting agent: $AGENT_ID"
    log_info "Type: $AGENT_TYPE"
    log_info "Poll interval: ${POLL_INTERVAL}s"
    log_info "Database: $AGENT_DB_PATH"
    log_info "========================================="

    # Register agent
    register_agent

    # Check for messages
    log_info "Checking for startup messages..."
    local messages=$(receive_messages "$AGENT_ID")
    if [ -n "$messages" ] && [ "$messages" != "[]" ]; then
        log_info "Received messages:"
        echo "$messages" | jq -r '.[] | "  [\(.topic)] \(.payload | @json)"'
    fi

    log_info "Entering main loop (Ctrl+C to stop)..."
    echo

    local iteration=0
    while true; do
        iteration=$((iteration + 1))

        # Send heartbeat every iteration
        heartbeat

        # Check for messages
        local messages=$(receive_messages "$AGENT_ID")
        if [ -n "$messages" ] && [ "$messages" != "[]" ]; then
            log_info "Received $(echo "$messages" | jq 'length') message(s)"
            echo "$messages" | jq -r '.[] | "  [\(.topic)] from \(.from_agent): \(.payload | @json)"'
        fi

        # Try to get a task
        log_info "[Iteration $iteration] Polling for tasks..."
        local task=$(dequeue_task "$AGENT_ID")

        if [ -n "$task" ] && [ "$task" != "[]" ] && [ "$task" != "null" ]; then
            # Process the task
            process_task "$task" || log_error "Task processing failed"
        else
            log_info "No tasks available, waiting..."
        fi

        # Wait before next poll
        sleep "$POLL_INTERVAL"
    done
}

# Run main loop
main
