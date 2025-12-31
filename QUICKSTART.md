# Quick Start Guide

Get up and running with the multi-agent system in 5 minutes.

## Prerequisites

Install required tools:

```bash
sudo dnf install tmux sqlite jq
```

## Installation

1. **Navigate to the setup directory:**
   ```bash
   cd /home/maxwell/multi-agent-setup
   ```

2. **Verify the installation:**
   ```bash
   ./verify-setup.sh
   ```

   This will check all prerequisites and initialize the database.

## Basic Usage

### Step 1: Start the System

```bash
./start-agents.sh
```

This launches a tmux session with:
- Control panel (window 0)
- 3 agent runners (windows 1-3)
- Monitoring dashboard (window 4)
- Log viewer (window 5)

**Tmux Navigation:**
- `Ctrl+b` then `w` - Show window list
- `Ctrl+b` then `0-5` - Jump to window
- `Ctrl+b` then `d` - Detach (keeps running in background)

### Step 2: Submit Your First Task

**Option A: Interactive (easiest)**
```bash
# In the control window or a new terminal
./quick-task.sh
```

Follow the prompts to create your first task.

**Option B: Command Line**
```bash
./task-cli.sh add code_review '{"file":"example.py"}' researcher 8
```

### Step 3: Monitor Progress

**Option A: Built-in Monitor (in tmux)**
- Switch to the "monitor" window (Ctrl+b then 4)
- Watch real-time updates

**Option B: Standalone Dashboard**
```bash
# In a new terminal
./monitor.sh --watch
```

### Step 4: Check Results

```bash
# List all tasks
./task-cli.sh list

# Get task details
./task-cli.sh status <task-id>

# View statistics
./task-cli.sh stats
```

## Common Tasks

### Submit Different Task Types

**Code Review:**
```bash
./task-cli.sh add code_review '{"file":"src/main.py"}' researcher 8
```

**Implement Feature:**
```bash
./task-cli.sh add implement_feature '{"specification":"Add user login"}' implementer 9
```

**Fix Bug:**
```bash
./task-cli.sh add fix_bug '{"description":"Null pointer in parser"}' implementer 7
```

**Analyze Code:**
```bash
./task-cli.sh add analyze '{"target":"auth module","question":"Security issues?"}' researcher 6
```

**Write Tests:**
```bash
./task-cli.sh add test '{"target":"user_service.py"}' reviewer 5
```

### Managing the Session

**Attach to running session:**
```bash
tmux attach -t multi-agent
```

**Detach without stopping:**
```
Ctrl+b then d
```

**Stop everything:**
```bash
tmux kill-session -t multi-agent
```

**Start fresh:**
```bash
# Kill existing session
tmux kill-session -t multi-agent 2>/dev/null

# Remove old data
rm -rf /tmp/multi-agent-system

# Start clean
./db-init.sh
./start-agents.sh
```

## Troubleshooting

**"Database not found"**
```bash
./db-init.sh
```

**"Session already exists"**
```bash
tmux kill-session -t multi-agent
./start-agents.sh
```

**Check agent logs:**
```bash
tail -f /tmp/multi-agent-system/logs/*.log
```

**Database queries:**
```bash
sqlite3 /tmp/multi-agent-system/agents.db
# Then run SQL commands
SELECT * FROM v_active_tasks;
```

## Next Steps

- **Read the full README:** `/home/maxwell/multi-agent-setup/README.md`
- **Explore examples:** `/home/maxwell/multi-agent-setup/EXAMPLES.md`
- **Customize agents:** Edit `AGENT_TYPES` in `start-agents.sh`
- **Adjust polling:** Set `POLL_INTERVAL` environment variable

## Architecture Overview

```
You submit tasks via CLI
         ↓
Tasks stored in SQLite
         ↓
Agents poll database (every 5s)
         ↓
Agent picks up task
         ↓
Claude Code processes task
         ↓
Results saved to database
         ↓
You view results via CLI/monitor
```

## File Locations

- **Scripts:** `/home/maxwell/multi-agent-setup/`
- **Database:** `/tmp/multi-agent-system/agents.db`
- **Logs:** `/tmp/multi-agent-system/logs/`
- **Task workspaces:** `/tmp/multi-agent-system/state/`

## Quick Reference

| Command | Description |
|---------|-------------|
| `./start-agents.sh` | Start the multi-agent system |
| `./quick-task.sh` | Interactive task submission |
| `./task-cli.sh add <type> <payload>` | Submit task |
| `./task-cli.sh list` | List all tasks |
| `./task-cli.sh stats` | Show statistics |
| `./monitor.sh --watch` | Live monitoring |
| `tmux attach -t multi-agent` | Attach to session |
| `tmux kill-session -t multi-agent` | Stop everything |

## Tips

1. **Start small** - Test with one simple task first
2. **Watch the logs** - They show what agents are doing
3. **Use priorities** - 9-10 for urgent, 5 for normal, 1-3 for low
4. **Clean up regularly** - Run `./task-cli.sh cleanup 7` to remove old tasks
5. **Monitor agent health** - Check heartbeats in the monitor window

## Getting Help

1. Check logs: `tail -f /tmp/multi-agent-system/logs/*.log`
2. Run verification: `./verify-setup.sh`
3. View stats: `./task-cli.sh stats`
4. Read the full docs: `README.md` and `EXAMPLES.md`

---

**You're ready to go!** Start with `./start-agents.sh` and experiment. 🚀
