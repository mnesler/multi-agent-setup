# Multi-Agent System with Claude Code and SQLite

A local development setup for orchestrating multiple Claude Code agents using tmux and SQLite for persistent task management and inter-agent communication.

## Features

- **SQLite-based task queue** - Persistent task storage with automatic retries
- **Inter-agent messaging** - Publish/subscribe style communication between agents
- **Tmux orchestration** - Each agent runs in an isolated tmux window
- **Real-time monitoring** - Live dashboard showing agent status and task progress
- **Task management CLI** - Easy command-line interface for task operations
- **Agent health tracking** - Heartbeat monitoring and status reporting
- **Flexible task types** - Support for code review, implementation, testing, and custom tasks

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SQLite Database                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │    Tasks     │  │   Messages   │  │    Agents    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
           ↑                  ↑                  ↑
           │                  │                  │
┌──────────┴──────────────────┴──────────────────┴───────────┐
│                     Tmux Session                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │  Agent 1   │  │  Agent 2   │  │  Agent 3   │  ...      │
│  │ (research) │  │ (implement)│  │  (review)  │           │
│  └────────────┘  └────────────┘  └────────────┘           │
│  ┌────────────┐  ┌────────────┐                           │
│  │  Monitor   │  │   Logs     │                           │
│  └────────────┘  └────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **tmux** - Terminal multiplexer
- **sqlite3** - Database engine
- **jq** - JSON processor
- **claude** (optional) - Claude Code CLI for actual task execution

Install on Fedora:
```bash
sudo dnf install tmux sqlite jq
```

## Quick Start

### 1. Initialize the Database

```bash
cd /home/maxwell/multi-agent-setup
chmod +x *.sh
./db-init.sh
```

This creates:
- SQLite database at `/tmp/multi-agent-system/agents.db`
- Log directory at `/tmp/multi-agent-system/logs`
- State directory at `/tmp/multi-agent-system/state`

### 2. Start the Multi-Agent System

```bash
./start-agents.sh
```

This launches a tmux session with:
- **control** window - Command panel for task management
- **agent-*** windows - One window per agent (default: 3 agents)
- **monitor** window - Real-time monitoring dashboard (4 panes)
- **logs** window - Aggregated log viewer

### 3. Submit Tasks

From the control window or any terminal:

```bash
# Quick interactive task submission
./quick-task.sh

# Or use the CLI directly
./task-cli.sh add code_review '{"file":"example.py"}' researcher 8
./task-cli.sh add implement_feature '{"specification":"Add user login"}' implementer 7
./task-cli.sh add fix_bug '{"description":"Memory leak in parser"}' 5
```

### 4. Monitor Progress

```bash
# View real-time dashboard
./monitor.sh --watch

# Or check stats
./task-cli.sh stats
./task-cli.sh list pending
```

## Directory Structure

```
/home/maxwell/multi-agent-setup/
├── init-db.sql           # Database schema
├── db-init.sh            # Database initialization script
├── task-utils.sh         # Task management functions
├── task-cli.sh           # CLI tool for task operations
├── agent-runner.sh       # Agent wrapper script
├── start-agents.sh       # Tmux orchestrator
├── monitor.sh            # Monitoring dashboard
├── quick-task.sh         # Interactive task submission (auto-generated)
└── README.md             # This file

/tmp/multi-agent-system/
├── agents.db             # SQLite database
├── .env                  # Environment variables
├── logs/                 # Agent logs
│   ├── agent-researcher-1.log
│   ├── agent-implementer-2.log
│   └── agent-reviewer-3.log
├── state/                # Task workspaces
│   └── task-*/
│       ├── input.json
│       ├── result.json
│       └── claude-output.txt
└── session-info.txt      # Session details
```

## Task Types

### 1. Code Review
```bash
./task-cli.sh add code_review '{"file":"src/main.py"}' researcher 8
```

### 2. Implement Feature
```bash
./task-cli.sh add implement_feature '{
  "specification": "Add user authentication with JWT tokens"
}' implementer 9
```

### 3. Fix Bug
```bash
./task-cli.sh add fix_bug '{
  "description": "Null pointer exception in login handler",
  "file": "auth.py"
}' implementer 7
```

### 4. Analyze
```bash
./task-cli.sh add analyze '{
  "target": "authentication module",
  "question": "What are the security vulnerabilities?"
}' researcher 6
```

### 5. Write Tests
```bash
./task-cli.sh add test '{"target":"user_service.py"}' reviewer 5
```

### 6. Custom Task
```bash
./task-cli.sh add custom '{
  "prompt": "Refactor the database connection pool for better performance"
}' implementer 8
```

## Inter-Agent Communication

### Send Message
```bash
# Send message to specific agent
./task-cli.sh send agent-researcher-1 agent-implementer-2 analysis '{
  "findings": "Authentication needs JWT support",
  "priority": "high"
}'

# Broadcast to all agents
./task-cli.sh send coordinator broadcast status '{"phase":"testing"}'
```

### Receive Messages
```bash
# Get all unread messages
./task-cli.sh receive agent-researcher-1

# Get messages for specific topic
./task-cli.sh receive agent-researcher-1 analysis
```

## Task Management

### List Tasks
```bash
# All tasks
./task-cli.sh list

# Pending tasks only
./task-cli.sh list pending

# In-progress tasks
./task-cli.sh list in_progress
```

### Check Task Status
```bash
./task-cli.sh status task-1234567890-5678
```

### Manual Task Completion (if needed)
```bash
./task-cli.sh complete task-123 '{
  "status": "success",
  "output": "Code review completed, found 3 issues"
}'
```

### Manual Task Failure
```bash
./task-cli.sh fail task-123 "Unable to access file"
```

### Cleanup Old Tasks
```bash
# Clean up tasks older than 7 days
./task-cli.sh cleanup 7
```

## Configuration

### Number of Agents
```bash
NUM_AGENTS=5 ./start-agents.sh
```

### Agent Types
Edit `start-agents.sh` and modify the `AGENT_TYPES` array:
```bash
AGENT_TYPES=("researcher" "implementer" "reviewer" "tester" "optimizer")
```

### Poll Interval
Modify the agent poll interval (default: 5 seconds):
```bash
export POLL_INTERVAL=10
./agent-runner.sh
```

### Database Location
```bash
export AGENT_DB_DIR=/path/to/custom/location
./db-init.sh
./start-agents.sh
```

## Tmux Commands

### Attach to Session
```bash
tmux attach -t multi-agent
```

### Detach from Session
Press `Ctrl+b` then `d`

### Switch Windows
Press `Ctrl+b` then `w` (shows window list)

Or use:
- `Ctrl+b` then `0-9` - Jump to window number
- `Ctrl+b` then `n` - Next window
- `Ctrl+b` then `p` - Previous window

### Kill Session
```bash
tmux kill-session -t multi-agent
```

### List All Sessions
```bash
tmux list-sessions
```

## Monitoring

### Real-time Dashboard
```bash
# Watch mode (refreshes every 5 seconds)
./monitor.sh --watch

# Custom refresh interval
./monitor.sh --watch 10

# One-time snapshot
./monitor.sh
```

### System Statistics
```bash
./task-cli.sh stats
```

### Agent Logs
```bash
# Tail all agent logs
tail -f /tmp/multi-agent-system/logs/*.log

# Specific agent
tail -f /tmp/multi-agent-system/logs/agent-researcher-1.log
```

## Advanced Usage

### Custom Agent Configuration

Create a custom agent type by modifying `start-agents.sh`:

```bash
AGENT_TYPES=("researcher" "implementer" "reviewer" "security-scanner")
```

Each agent type can have specialized behavior defined in the `build_prompt()` function in `agent-runner.sh`.

### Database Queries

Access the database directly:

```bash
sqlite3 /tmp/multi-agent-system/agents.db

# Example queries
SELECT * FROM v_active_tasks;
SELECT * FROM v_agent_health;
SELECT * FROM v_unread_messages;
```

### Task Priority System

Tasks are executed in priority order (1-10, higher = more urgent):
- **9-10**: Critical/urgent tasks
- **7-8**: High priority
- **5-6**: Normal priority
- **3-4**: Low priority
- **1-2**: Background tasks

### Retry Mechanism

Failed tasks automatically retry up to 3 times (configurable in `init-db.sql`):

```sql
UPDATE config SET value = '5' WHERE key = 'max_task_retries';
```

## Troubleshooting

### Database Locked
If you see "database is locked" errors:
```bash
# Check for lingering processes
lsof /tmp/multi-agent-system/agents.db

# Kill zombie agents
tmux kill-session -t multi-agent
```

### Agent Not Picking Up Tasks
```bash
# Check agent status
./task-cli.sh stats

# View agent logs
tail -f /tmp/multi-agent-system/logs/agent-*.log

# Check for stale heartbeats
sqlite3 /tmp/multi-agent-system/agents.db "SELECT * FROM v_agent_health;"
```

### Reset Everything
```bash
# Kill session
tmux kill-session -t multi-agent

# Remove database
rm -rf /tmp/multi-agent-system

# Reinitialize
./db-init.sh
./start-agents.sh
```

## Integration with Claude Code

The system is designed to work with Claude Code agents. To integrate:

1. **Ensure Claude Code is installed and accessible**
2. **Agents will automatically invoke Claude** via the `execute_claude_task()` function
3. **Customize prompts** in the `build_prompt()` function in `agent-runner.sh`

### Example: Running Claude Code with Tasks

The agent runner automatically constructs prompts based on task type and passes them to Claude Code:

```bash
# Task is automatically converted to Claude prompt
# Task: {"task_type": "code_review", "payload": {"file": "main.py"}}
#
# Becomes Claude prompt:
# "Review the code in main.py and provide feedback on code quality,
#  potential bugs, and improvements."
```

## Performance Considerations

- **SQLite can handle 100,000+ tasks** efficiently with proper indexing
- **Poll interval** affects responsiveness vs CPU usage (default: 5s)
- **Number of agents** should match your workload (start with 3-5)
- **Log rotation** should be implemented for long-running systems

## Future Enhancements

- [ ] Web-based monitoring dashboard
- [ ] Agent specialization via custom prompts
- [ ] Task dependencies and workflows
- [ ] Metrics and analytics
- [ ] Remote agent support (network sockets)
- [ ] Integration with CI/CD pipelines
- [ ] Task scheduling and cron-like triggers

## License

This is a development tool for local use. Modify and adapt as needed for your workflow.

## Support

For issues or questions:
1. Check logs in `/tmp/multi-agent-system/logs/`
2. View session info: `cat /tmp/multi-agent-system/session-info.txt`
3. Run diagnostics: `./task-cli.sh stats`
