#!/bin/bash
# Database initialization script for multi-agent system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${AGENT_DB_DIR:-/tmp/multi-agent-system}"
DB_PATH="${DB_DIR}/agents.db"
SCHEMA_FILE="${SCRIPT_DIR}/init-db.sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if sqlite3 is installed
if ! command -v sqlite3 &> /dev/null; then
    log_error "sqlite3 is not installed. Please install it first."
    echo "On Fedora: sudo dnf install sqlite"
    exit 1
fi

# Create database directory
mkdir -p "$DB_DIR"
log_info "Database directory: $DB_DIR"

# Initialize database with schema
if [ -f "$DB_PATH" ]; then
    log_warn "Database already exists at $DB_PATH"
    read -p "Do you want to reinitialize it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$DB_PATH"
        log_info "Removed existing database"
    else
        log_info "Keeping existing database"
        exit 0
    fi
fi

log_info "Creating database at $DB_PATH"
sqlite3 "$DB_PATH" < "$SCHEMA_FILE"

if [ $? -eq 0 ]; then
    log_info "Database initialized successfully"
else
    log_error "Failed to initialize database"
    exit 1
fi

# Set permissions
chmod 666 "$DB_PATH"

# Display database info
log_info "Database statistics:"
echo "  Tables: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")"
echo "  Views: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='view';")"
echo "  Location: $DB_PATH"

# Create helper directories
mkdir -p "$DB_DIR/logs"
mkdir -p "$DB_DIR/state"
mkdir -p "$DB_DIR/scripts"

log_info "Created helper directories:"
echo "  Logs: $DB_DIR/logs"
echo "  State: $DB_DIR/state"
echo "  Scripts: $DB_DIR/scripts"

# Export environment variable for other scripts
echo "export AGENT_DB_PATH='$DB_PATH'" > "$DB_DIR/.env"
log_info "Environment file created at $DB_DIR/.env"
log_info "Source it with: source $DB_DIR/.env"

echo
log_info "Setup complete! You can now use the multi-agent system."
