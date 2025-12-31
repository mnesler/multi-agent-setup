#!/bin/bash
# Tmux orchestrator for multi-agent system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
SESSION_NAME="${SESSION_NAME:-multi-agent}"
NUM_AGENTS="${NUM_AGENTS:-3}"
DB_DIR="${AGENT_DB_DIR:-/tmp/multi-agent-system}"
DB_PATH="${DB_DIR}/agents.db"

# Agent types (customize based on your needs)
AGENT_TYPES=("researcher" "implementer" "reviewer")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v tmux &> /dev/null; then
        log_error "tmux is not installed"
        exit 1
    fi

    if ! command -v sqlite3 &> /dev/null; then
        log_error "sqlite3 is not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        exit 1
    fi

    if [ ! -f "$DB_PATH" ]; then
        log_warn "Database not found, initializing..."
        bash "$SCRIPT_DIR/db-init.sh"
    fi

    log_info "All prerequisites met"
}

# Check if session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_warn "Session '$SESSION_NAME' already exists"
    read -p "Do you want to kill it and create a new one? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        tmux kill-session -t "$SESSION_NAME"
        log_info "Killed existing session"
    else
        log_info "Attaching to existing session..."
        tmux attach-session -t "$SESSION_NAME"
        exit 0
    fi
fi

# Run prerequisite check
check_prerequisites

log_info "Starting multi-agent system with $NUM_AGENTS agents"
log_info "Session name: $SESSION_NAME"
log_info "Database: $DB_PATH"

# Source environment
source "$DB_DIR/.env"

# Create main session with control panel
log_info "Creating tmux session..."
tmux new-session -d -s "$SESSION_NAME" -n "control"

# Set up control panel
tmux send-keys -t "$SESSION_NAME:control" "cd '$SCRIPT_DIR'" Enter
tmux send-keys -t "$SESSION_NAME:control" "clear" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '=== Multi-Agent Control Panel ==='" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo 'Available commands:'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '  ./task-cli.sh add <type> <payload> [agent] [priority] - Add task'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '  ./task-cli.sh list [status] - List tasks'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '  ./task-cli.sh stats - Show statistics'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '  ./task-cli.sh help - Show all commands'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo ''" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo 'Quick start:'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo '  ./task-cli.sh add code_review '\''{"file":"example.py"}'\'' researcher 8'" Enter
tmux send-keys -t "$SESSION_NAME:control" "echo ''" Enter

# Create agent windows
for i in $(seq 1 $NUM_AGENTS); do
    # Get agent type (cycle through available types)
    agent_type_idx=$(( (i - 1) % ${#AGENT_TYPES[@]} ))
    agent_type="${AGENT_TYPES[$agent_type_idx]}"
    agent_id="agent-${agent_type}-${i}"

    log_info "Creating agent window: $agent_id (type: $agent_type)"

    # Create window for this agent
    tmux new-window -t "$SESSION_NAME" -n "$agent_id"

    # Start agent runner
    tmux send-keys -t "$SESSION_NAME:$agent_id" \
        "export AGENT_ID='$agent_id'; export AGENT_TYPE='$agent_type'; export AGENT_DB_PATH='$DB_PATH'; cd '$SCRIPT_DIR' && bash agent-runner.sh" Enter
done

# Create monitoring dashboard window
log_info "Creating monitoring dashboard..."
tmux new-window -t "$SESSION_NAME" -n "monitor"

# Set up split panes for monitoring
tmux split-window -h -t "$SESSION_NAME:monitor"
tmux split-window -v -t "$SESSION_NAME:monitor.0"
tmux split-window -v -t "$SESSION_NAME:monitor.2"

# Top-left: Task queue
tmux send-keys -t "$SESSION_NAME:monitor.0" \
    "watch -n 2 -c \"echo '=== Pending Tasks ===' && sqlite3 -box '$DB_PATH' 'SELECT id, task_type, assigned_to, priority FROM tasks WHERE status=\\\"pending\\\" ORDER BY priority DESC LIMIT 10'\"" Enter

# Bottom-left: Active tasks
tmux send-keys -t "$SESSION_NAME:monitor.1" \
    "watch -n 2 -c \"echo '=== Active Tasks ===' && sqlite3 -box '$DB_PATH' 'SELECT id, task_type, assigned_to FROM tasks WHERE status=\\\"in_progress\\\" LIMIT 10'\"" Enter

# Top-right: Agent status
tmux send-keys -t "$SESSION_NAME:monitor.2" \
    "watch -n 2 -c \"echo '=== Agent Status ===' && sqlite3 -box '$DB_PATH' 'SELECT agent_id, status, total_tasks_completed as completed, total_tasks_failed as failed FROM agents ORDER BY agent_id'\"" Enter

# Bottom-right: System stats
tmux send-keys -t "$SESSION_NAME:monitor.3" \
    "watch -n 5 \"cd '$SCRIPT_DIR' && ./task-cli.sh stats\"" Enter

# Create logs window
log_info "Creating logs window..."
tmux new-window -t "$SESSION_NAME" -n "logs"
tmux send-keys -t "$SESSION_NAME:logs" \
    "tail -f $DB_DIR/logs/*.log 2>/dev/null || echo 'Waiting for logs...'" Enter

# Select control panel as default
tmux select-window -t "$SESSION_NAME:control"

# Create helper script for easy task submission
cat > "$SCRIPT_DIR/quick-task.sh" <<'TASKEOF'
#!/bin/bash
# Quick task submission helper

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Quick Task Submission ==="
echo
echo "Task types:"
echo "  1. code_review - Review code files"
echo "  2. implement_feature - Implement new features"
echo "  3. fix_bug - Fix bugs"
echo "  4. analyze - Analyze code/systems"
echo "  5. test - Write tests"
echo "  6. custom - Custom task"
echo

read -p "Select task type (1-6): " choice

case $choice in
    1) task_type="code_review"
       read -p "File to review: " file
       payload="{\"file\":\"$file\"}"
       ;;
    2) task_type="implement_feature"
       read -p "Feature specification: " spec
       payload="{\"specification\":\"$spec\"}"
       ;;
    3) task_type="fix_bug"
       read -p "Bug description: " desc
       read -p "File (optional): " file
       if [ -n "$file" ]; then
           payload="{\"description\":\"$desc\",\"file\":\"$file\"}"
       else
           payload="{\"description\":\"$desc\"}"
       fi
       ;;
    4) task_type="analyze"
       read -p "Target to analyze: " target
       read -p "Question (optional): " question
       if [ -n "$question" ]; then
           payload="{\"target\":\"$target\",\"question\":\"$question\"}"
       else
           payload="{\"target\":\"$target\"}"
       fi
       ;;
    5) task_type="test"
       read -p "Target to test: " target
       payload="{\"target\":\"$target\"}"
       ;;
    6) task_type="custom"
       read -p "Custom prompt: " prompt
       payload="{\"prompt\":\"$prompt\"}"
       ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

read -p "Agent ID (leave empty for any): " agent
read -p "Priority (1-10, default 5): " priority
priority=${priority:-5}

echo
echo "Submitting task..."
task_id=$("$SCRIPT_DIR/task-cli.sh" add "$task_type" "$payload" "$agent" "$priority")
echo "Task created: $task_id"
TASKEOF

chmod +x "$SCRIPT_DIR/quick-task.sh"

# Create session info file
cat > "$DB_DIR/session-info.txt" <<EOF
Multi-Agent System Session Information
======================================

Session Name: $SESSION_NAME
Database: $DB_PATH
Number of Agents: $NUM_AGENTS
Started: $(date)

Tmux Windows:
  - control: Control panel with task management commands
  - agent-*: Agent runner windows (one per agent)
  - monitor: Real-time monitoring dashboard
  - logs: Aggregated log viewer

Commands:
  - Attach to session: tmux attach -t $SESSION_NAME
  - Kill session: tmux kill-session -t $SESSION_NAME
  - List windows: tmux list-windows -t $SESSION_NAME

Quick Task Submission:
  cd $SCRIPT_DIR && ./quick-task.sh

Task Management:
  ./task-cli.sh add <type> <payload> [agent] [priority]
  ./task-cli.sh list
  ./task-cli.sh stats

Agent Types:
$(printf '  - %s\n' "${AGENT_TYPES[@]}")

Logs Directory: $DB_DIR/logs
State Directory: $DB_DIR/state
EOF

log_info "Session created successfully!"
log_info "Session info saved to: $DB_DIR/session-info.txt"
echo
log_info "Attaching to session in 2 seconds..."
log_info "Use 'Ctrl+b d' to detach, 'Ctrl+b w' to switch windows"
sleep 2

# Attach to the session
tmux attach-session -t "$SESSION_NAME"
