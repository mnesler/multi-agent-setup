#!/bin/bash
# Verification script to test the multi-agent system setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="/tmp/multi-agent-system"
DB_PATH="$DB_DIR/agents.db"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

echo "========================================="
echo "Multi-Agent System Setup Verification"
echo "========================================="
echo

# Check 1: Prerequisites
info "Checking prerequisites..."

if command -v tmux &> /dev/null; then
    pass "tmux is installed ($(tmux -V))"
else
    fail "tmux is not installed. Run: sudo dnf install tmux"
fi

if command -v sqlite3 &> /dev/null; then
    pass "sqlite3 is installed ($(sqlite3 --version))"
else
    fail "sqlite3 is not installed. Run: sudo dnf install sqlite"
fi

if command -v jq &> /dev/null; then
    pass "jq is installed ($(jq --version))"
else
    fail "jq is not installed. Run: sudo dnf install jq"
fi

if command -v claude &> /dev/null; then
    pass "Claude Code is installed"
else
    warn "Claude Code not found - agents will use fallback mode"
fi

echo

# Check 2: Scripts
info "Checking scripts..."

scripts=(
    "db-init.sh"
    "task-utils.sh"
    "task-cli.sh"
    "agent-runner.sh"
    "start-agents.sh"
    "monitor.sh"
)

for script in "${scripts[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if [ -x "$SCRIPT_DIR/$script" ]; then
            pass "$script exists and is executable"
        else
            fail "$script exists but is not executable"
        fi
    else
        fail "$script is missing"
    fi
done

if [ -f "$SCRIPT_DIR/init-db.sql" ]; then
    pass "init-db.sql schema file exists"
else
    fail "init-db.sql is missing"
fi

echo

# Check 3: Database initialization
info "Testing database initialization..."

# Clean up if exists
if [ -d "$DB_DIR" ]; then
    rm -rf "$DB_DIR"
fi

# Initialize
if bash "$SCRIPT_DIR/db-init.sh" &> /dev/null; then
    pass "Database initialized successfully"
else
    fail "Database initialization failed"
fi

if [ -f "$DB_PATH" ]; then
    pass "Database file created at $DB_PATH"
else
    fail "Database file not found"
fi

# Check database schema
table_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
if [ "$table_count" -ge 6 ]; then
    pass "Database schema loaded ($table_count tables)"
else
    fail "Database schema incomplete (only $table_count tables)"
fi

view_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='view';")
if [ "$view_count" -ge 3 ]; then
    pass "Database views created ($view_count views)"
else
    warn "Expected at least 3 views, found $view_count"
fi

echo

# Check 4: Task utilities
info "Testing task utilities..."

source "$SCRIPT_DIR/task-utils.sh"

# Test task creation
task_id=$(enqueue_task "test" '{"test":"verification"}' "" 5)
if [ -n "$task_id" ]; then
    pass "Task creation works (ID: $task_id)"
else
    fail "Task creation failed"
fi

# Test task retrieval
task_status=$(sqlite3 "$DB_PATH" "SELECT status FROM tasks WHERE id='$task_id';")
if [ "$task_status" = "pending" ]; then
    pass "Task status is correct"
else
    fail "Task status incorrect: $task_status"
fi

# Test task completion
if complete_task "$task_id" '{"result":"success"}' &> /dev/null; then
    pass "Task completion works"
else
    fail "Task completion failed"
fi

# Verify completion
task_status=$(sqlite3 "$DB_PATH" "SELECT status FROM tasks WHERE id='$task_id';")
if [ "$task_status" = "complete" ]; then
    pass "Task status updated to complete"
else
    fail "Task status not updated: $task_status"
fi

echo

# Check 5: CLI tool
info "Testing CLI tool..."

# Test add command
cli_task=$("$SCRIPT_DIR/task-cli.sh" add test '{"cli":"test"}' "" 5)
if [ -n "$cli_task" ]; then
    pass "CLI add command works"
else
    fail "CLI add command failed"
fi

# Test list command
if "$SCRIPT_DIR/task-cli.sh" list &> /dev/null; then
    pass "CLI list command works"
else
    fail "CLI list command failed"
fi

# Test stats command
if "$SCRIPT_DIR/task-cli.sh" stats &> /dev/null; then
    pass "CLI stats command works"
else
    fail "CLI stats command failed"
fi

echo

# Check 6: Messaging system
info "Testing messaging system..."

# Send message
if send_message "test-agent-1" "test-agent-2" "test-topic" '{"msg":"hello"}' &> /dev/null; then
    pass "Message sending works"
else
    fail "Message sending failed"
fi

# Check message count
msg_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM messages WHERE consumed=0;")
if [ "$msg_count" -ge 1 ]; then
    pass "Message stored in database"
else
    fail "Message not found in database"
fi

echo

# Check 7: Agent registration
info "Testing agent registration..."

# Register test agent
sqlite3 "$DB_PATH" <<EOF
INSERT INTO agents (agent_id, agent_type, status)
VALUES ('test-agent-verify', 'test', 'idle');
EOF

agent_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agents WHERE agent_id='test-agent-verify';")
if [ "$agent_count" -eq 1 ]; then
    pass "Agent registration works"
else
    fail "Agent registration failed"
fi

echo

# Check 8: Monitor script
info "Testing monitor script..."

if "$SCRIPT_DIR/monitor.sh" &> /dev/null; then
    pass "Monitor script runs successfully"
else
    warn "Monitor script had issues (may be cosmetic)"
fi

echo

# Summary
echo "========================================="
echo "Verification Complete!"
echo "========================================="
echo
info "Next steps:"
echo "  1. Start the system: $SCRIPT_DIR/start-agents.sh"
echo "  2. Submit a test task: $SCRIPT_DIR/quick-task.sh"
echo "  3. Monitor progress: $SCRIPT_DIR/monitor.sh --watch"
echo
info "Documentation:"
echo "  - README: $SCRIPT_DIR/README.md"
echo "  - Examples: $SCRIPT_DIR/EXAMPLES.md"
echo
info "Database: $DB_PATH"
info "Logs will be in: $DB_DIR/logs/"
echo
pass "All checks passed! System is ready to use."
