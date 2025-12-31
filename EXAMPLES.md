# Multi-Agent System - Example Workflows

This document provides practical examples of using the multi-agent system for common development tasks.

## Table of Contents

1. [Basic Workflows](#basic-workflows)
2. [Code Review Pipeline](#code-review-pipeline)
3. [Feature Development Workflow](#feature-development-workflow)
4. [Bug Triage and Fix](#bug-triage-and-fix)
5. [Testing Workflow](#testing-workflow)
6. [Inter-Agent Collaboration](#inter-agent-collaboration)
7. [Custom Automation](#custom-automation)

---

## Basic Workflows

### Example 1: Single Task Submission

```bash
# Start the system
./start-agents.sh

# In another terminal or the control window
./task-cli.sh add code_review '{
  "file": "/home/maxwell/project/src/auth.py"
}' researcher 8

# Monitor progress
./monitor.sh --watch
```

**What happens:**
1. Task is added to database with priority 8
2. Researcher agent picks up the task in next poll cycle (≤5s)
3. Agent constructs Claude prompt: "Review the code in /home/maxwell/project/src/auth.py..."
4. Claude analyzes the file
5. Results are stored in database and task is marked complete

### Example 2: Batch Task Submission

```bash
# Submit multiple tasks at once
for file in src/*.py; do
  ./task-cli.sh add code_review "{\"file\":\"$file\"}" researcher 5
done

# Check queue
./task-cli.sh list pending
```

---

## Code Review Pipeline

### Scenario: Review Pull Request Changes

```bash
#!/bin/bash
# review-pr.sh - Review all changed files in a PR

PR_FILES=$(git diff --name-only origin/main...HEAD)

echo "Submitting code review tasks for PR files..."

for file in $PR_FILES; do
  echo "  - $file"

  # Assign higher priority to critical files
  priority=5
  if [[ $file == *"test"* ]]; then
    priority=6
  elif [[ $file == *"auth"* ]] || [[ $file == *"security"* ]]; then
    priority=9
  fi

  ./task-cli.sh add code_review "{
    \"file\": \"$file\",
    \"context\": \"PR review\"
  }" researcher $priority
done

echo "Submitted $(echo "$PR_FILES" | wc -l) review tasks"

# Monitor completion
echo "Monitoring progress..."
while [ $(./task-cli.sh list pending | wc -l) -gt 1 ]; do
  sleep 5
  clear
  ./task-cli.sh stats
done

echo "All reviews complete!"

# Aggregate results
sqlite3 /tmp/multi-agent-system/agents.db <<EOF
SELECT
  json_extract(payload, '$.file') as file,
  json_extract(result, '$.output') as review
FROM tasks
WHERE task_type = 'code_review'
  AND status = 'complete'
  AND datetime(completed_at) > datetime('now', '-10 minutes')
ORDER BY completed_at;
EOF
```

---

## Feature Development Workflow

### Scenario: Multi-Stage Feature Implementation

This workflow demonstrates coordinating multiple agents for a complex feature.

```bash
#!/bin/bash
# implement-feature.sh - Coordinate feature development

FEATURE="User authentication with JWT tokens"

echo "=== Feature Implementation Workflow ==="
echo "Feature: $FEATURE"
echo

# Step 1: Research phase
echo "[1/4] Research phase..."
task1=$(./task-cli.sh add analyze "{
  \"target\": \"existing authentication system\",
  \"question\": \"What changes are needed to add JWT support?\"
}" researcher 9)

echo "Research task: $task1"

# Wait for research to complete
while [ "$(./task-cli.sh status $task1 | jq -r '.[0].status')" != "complete" ]; do
  sleep 5
done

echo "Research complete!"

# Get research findings
research_output=$(./task-cli.sh status $task1 | jq -r '.[0].result.output')

# Step 2: Implementation phase
echo "[2/4] Implementation phase..."
task2=$(./task-cli.sh add implement_feature "{
  \"specification\": \"$FEATURE\",
  \"research_notes\": \"$research_output\"
}" implementer 9)

echo "Implementation task: $task2"

# Wait for implementation
while [ "$(./task-cli.sh status $task2 | jq -r '.[0].status')" != "complete" ]; do
  sleep 5
  echo -n "."
done

echo
echo "Implementation complete!"

# Step 3: Code review
echo "[3/4] Code review phase..."
task3=$(./task-cli.sh add code_review "{
  \"file\": \"src/auth/jwt.py\",
  \"context\": \"New JWT implementation - check security\"
}" reviewer 9)

# Step 4: Testing
echo "[4/4] Testing phase..."
task4=$(./task-cli.sh add test "{
  \"target\": \"src/auth/jwt.py\"
}" reviewer 8)

# Wait for both review and testing
echo "Waiting for review and testing..."
while [ "$(./task-cli.sh status $task3 | jq -r '.[0].status')" != "complete" ] || \
      [ "$(./task-cli.sh status $task4 | jq -r '.[0].status')" != "complete" ]; do
  sleep 5
  echo -n "."
done

echo
echo "=== Feature Implementation Complete ==="
echo
echo "Task Summary:"
./task-cli.sh status $task1 | jq -r '.[0] | "  Research: \(.status)"'
./task-cli.sh status $task2 | jq -r '.[0] | "  Implementation: \(.status)"'
./task-cli.sh status $task3 | jq -r '.[0] | "  Review: \(.status)"'
./task-cli.sh status $task4 | jq -r '.[0] | "  Testing: \(.status)"'
```

---

## Bug Triage and Fix

### Scenario: Automated Bug Handling

```bash
#!/bin/bash
# bug-workflow.sh - Triage and fix bugs

BUG_DESCRIPTION="Application crashes when user submits empty form"
BUG_FILE="src/forms/validation.py"

echo "=== Bug Triage Workflow ==="

# Step 1: Analysis
echo "[1/3] Analyzing bug..."
analysis_task=$(./task-cli.sh add analyze "{
  \"target\": \"$BUG_FILE\",
  \"question\": \"Why does the application crash with empty form submission? Identify root cause.\"
}" researcher 10)

# Wait for analysis
while [ "$(./task-cli.sh status $analysis_task | jq -r '.[0].status')" != "complete" ]; do
  sleep 3
done

root_cause=$(./task-cli.sh status $analysis_task | jq -r '.[0].result.output')
echo "Root cause identified: $root_cause"

# Step 2: Fix implementation
echo "[2/3] Implementing fix..."
fix_task=$(./task-cli.sh add fix_bug "{
  \"description\": \"$BUG_DESCRIPTION\",
  \"file\": \"$BUG_FILE\",
  \"root_cause\": \"$root_cause\"
}" implementer 10)

# Wait for fix
while [ "$(./task-cli.sh status $fix_task | jq -r '.[0].status')" != "complete" ]; do
  sleep 3
  echo -n "."
done

echo
echo "Fix implemented!"

# Step 3: Verification
echo "[3/3] Verifying fix..."
test_task=$(./task-cli.sh add test "{
  \"target\": \"$BUG_FILE\",
  \"test_type\": \"regression\",
  \"bug_description\": \"$BUG_DESCRIPTION\"
}" reviewer 9)

# Wait for testing
while [ "$(./task-cli.sh status $test_task | jq -r '.[0].status')" != "complete" ]; do
  sleep 3
done

echo "Bug workflow complete!"
echo
echo "Summary:"
echo "  Analysis: $(./task-cli.sh status $analysis_task | jq -r '.[0].status')"
echo "  Fix: $(./task-cli.sh status $fix_task | jq -r '.[0].status')"
echo "  Verification: $(./task-cli.sh status $test_task | jq -r '.[0].status')"
```

---

## Testing Workflow

### Scenario: Comprehensive Test Suite Generation

```bash
#!/bin/bash
# generate-tests.sh - Generate tests for all modules

echo "=== Test Generation Workflow ==="

# Find all Python files without corresponding test files
for src_file in src/**/*.py; do
  # Skip __init__.py
  if [[ $src_file == *"__init__.py" ]]; then
    continue
  fi

  # Check if test file exists
  test_file="tests/test_$(basename $src_file)"

  if [ ! -f "$test_file" ]; then
    echo "Missing tests for: $src_file"

    # Submit test generation task
    ./task-cli.sh add test "{
      \"target\": \"$src_file\",
      \"test_file\": \"$test_file\",
      \"coverage_target\": 80
    }" reviewer 6
  fi
done

# Monitor progress
echo
echo "Monitoring test generation..."
./monitor.sh --watch 10
```

---

## Inter-Agent Collaboration

### Scenario: Coordinated Multi-Agent Task

This example shows agents communicating to coordinate work.

```bash
#!/bin/bash
# collaborative-refactor.sh - Multiple agents collaborate on refactoring

MODULE="user_management"

echo "=== Collaborative Refactoring Workflow ==="

# Coordinator sends initial message to all agents
./task-cli.sh send coordinator broadcast project_start "{
  \"project\": \"refactor_$MODULE\",
  \"phase\": \"planning\"
}"

# Agent 1: Analyze current structure
./task-cli.sh add analyze "{
  \"target\": \"src/$MODULE/\",
  \"question\": \"What are the architectural issues?\"
}" agent-researcher-1 9

# Wait a bit for research
sleep 15

# Agent 1 sends findings to Agent 2
./task-cli.sh send agent-researcher-1 agent-implementer-2 findings "{
  \"issues\": [\"tight coupling\", \"missing abstraction\", \"duplicate code\"],
  \"recommendation\": \"Introduce service layer pattern\"
}"

# Agent 2: Implement refactoring based on findings
./task-cli.sh add custom "{
  \"prompt\": \"Refactor $MODULE based on service layer pattern. Check messages for research findings.\"
}" agent-implementer-2 9

# Wait for implementation
sleep 30

# Agent 2 notifies Agent 3 that review is needed
./task-cli.sh send agent-implementer-2 agent-reviewer-3 review_request "{
  \"module\": \"$MODULE\",
  \"changes\": \"service layer pattern implemented\"
}"

# Agent 3: Review refactoring
./task-cli.sh add code_review "{
  \"file\": \"src/$MODULE/service.py\",
  \"context\": \"Refactoring review - check messages\"
}" agent-reviewer-3 8

# Monitor messages
echo
echo "Monitoring inter-agent communication..."
watch -n 3 "./task-cli.sh receive coordinator | jq '.'"
```

### Example: Agent Handoff Pattern

```bash
#!/bin/bash
# agent-handoff.sh - Demonstrates task handoff between agents

# Agent 1 does research and hands off to Agent 2
research_task=$(./task-cli.sh add analyze "{
  \"target\": \"payment processing module\"
}" agent-researcher-1 9)

# Wait for research
while [ "$(./task-cli.sh status $research_task | jq -r '.[0].status')" != "complete" ]; do
  sleep 2
done

# Agent 1 sends results to Agent 2
./task-cli.sh send agent-researcher-1 agent-implementer-2 handoff "{
  \"task_id\": \"$research_task\",
  \"next_action\": \"implement_improvements\",
  \"research_complete\": true
}"

# Agent 2 receives message and starts work
./task-cli.sh add implement_feature "{
  \"specification\": \"Implement improvements identified in research task $research_task\",
  \"check_messages\": true
}" agent-implementer-2 9
```

---

## Custom Automation

### Scenario: Nightly Code Quality Check

```bash
#!/bin/bash
# nightly-check.sh - Automated nightly quality checks

echo "=== Nightly Code Quality Check ==="
echo "Started: $(date)"

# 1. Run code reviews on all modified files from last 24h
echo "[1/4] Reviewing recent changes..."
git diff --name-only HEAD@{1.day.ago} HEAD | while read file; do
  if [[ $file == *.py ]]; then
    ./task-cli.sh add code_review "{\"file\":\"$file\"}" researcher 5
  fi
done

# 2. Check for security issues
echo "[2/4] Security scan..."
./task-cli.sh add analyze "{
  \"target\": \"entire codebase\",
  \"question\": \"Identify potential security vulnerabilities\"
}" researcher 8

# 3. Code complexity analysis
echo "[3/4] Complexity analysis..."
./task-cli.sh add analyze "{
  \"target\": \"src/\",
  \"question\": \"Which functions have cyclomatic complexity > 10?\"
}" researcher 6

# 4. Test coverage check
echo "[4/4] Test coverage..."
./task-cli.sh add custom "{
  \"prompt\": \"Analyze test coverage and identify untested code paths\"
}" reviewer 7

# Wait for all tasks to complete
echo
echo "Waiting for tasks to complete..."
while [ $(./task-cli.sh list in_progress | wc -l) -gt 1 ] || \
      [ $(./task-cli.sh list pending | wc -l) -gt 1 ]; do
  sleep 10
  clear
  ./monitor.sh
done

# Generate report
echo
echo "=== Nightly Report ==="
sqlite3 /tmp/multi-agent-system/agents.db <<EOF
.mode markdown
SELECT
  task_type as "Check Type",
  status as "Status",
  substr(json_extract(result, '$.output'), 1, 100) as "Summary"
FROM tasks
WHERE datetime(created_at) > datetime('now', '-1 hour')
ORDER BY created_at;
EOF

echo
echo "Completed: $(date)"
```

### Scenario: CI/CD Integration

```bash
#!/bin/bash
# ci-integration.sh - Integrate with CI/CD pipeline

set -e

echo "=== CI/CD Pre-Commit Checks ==="

# Start agents in background
./start-agents.sh &
sleep 10  # Wait for agents to initialize

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
  echo "No files staged for commit"
  exit 0
fi

echo "Analyzing $(echo "$STAGED_FILES" | wc -l) staged files..."

# Submit analysis tasks
task_ids=()
for file in $STAGED_FILES; do
  # Only check code files
  if [[ $file =~ \.(py|js|ts|jsx|tsx)$ ]]; then
    task_id=$(./task-cli.sh add code_review "{
      \"file\": \"$file\",
      \"context\": \"pre-commit check\"
    }" reviewer 10)
    task_ids+=("$task_id")
  fi
done

# Wait for all tasks
echo "Waiting for analysis to complete..."
all_complete=false
while [ "$all_complete" = false ]; do
  all_complete=true
  for task_id in "${task_ids[@]}"; do
    status=$(./task-cli.sh status "$task_id" | jq -r '.[0].status')
    if [ "$status" != "complete" ] && [ "$status" != "failed" ]; then
      all_complete=false
      break
    fi
  done
  sleep 2
done

# Check for failures or critical issues
echo
echo "=== Analysis Results ==="
has_issues=false
for task_id in "${task_ids[@]}"; do
  result=$(./task-cli.sh status "$task_id" | jq -r '.[0].result.output')

  # Check if result contains keywords indicating issues
  if echo "$result" | grep -qiE "(error|critical|security|vulnerability)"; then
    echo "⚠️  Issues found in $task_id"
    echo "$result"
    has_issues=true
  else
    echo "✓ $task_id passed"
  fi
done

# Cleanup
tmux kill-session -t multi-agent 2>/dev/null || true

if [ "$has_issues" = true ]; then
  echo
  echo "❌ Pre-commit checks failed. Please fix issues before committing."
  exit 1
else
  echo
  echo "✅ All pre-commit checks passed!"
  exit 0
fi
```

---

## Advanced Patterns

### Pattern: Priority Queue Management

```bash
#!/bin/bash
# priority-management.sh - Dynamic priority adjustment

# High priority: Security and auth
for file in src/auth/*.py src/security/*.py; do
  ./task-cli.sh add code_review "{\"file\":\"$file\"}" researcher 10
done

# Medium priority: Core business logic
for file in src/business/*.py; do
  ./task-cli.sh add code_review "{\"file\":\"$file\"}" researcher 7
done

# Low priority: Utilities
for file in src/utils/*.py; do
  ./task-cli.sh add code_review "{\"file\":\"$file\"}" researcher 3
done

# Monitor and re-prioritize based on findings
while true; do
  # Check if any high-priority tasks found critical issues
  critical_count=$(sqlite3 /tmp/multi-agent-system/agents.db \
    "SELECT COUNT(*) FROM tasks
     WHERE status='complete'
     AND priority >= 8
     AND json_extract(result, '$.output') LIKE '%critical%'")

  if [ "$critical_count" -gt 0 ]; then
    echo "Critical issues found! Elevating related task priorities..."
    # Implement priority elevation logic
  fi

  sleep 30
done
```

### Pattern: Agent Specialization

```bash
#!/bin/bash
# specialized-workflow.sh - Route tasks to specialized agents

route_task() {
  local file="$1"
  local agent="researcher"  # default

  # Route based on file type/content
  if [[ $file == *"security"* ]] || [[ $file == *"auth"* ]]; then
    agent="security-specialist"
  elif [[ $file == *"test"* ]]; then
    agent="test-specialist"
  elif [[ $file == *"api"* ]]; then
    agent="api-specialist"
  fi

  ./task-cli.sh add code_review "{\"file\":\"$file\"}" "$agent" 7
}

# Process all files with intelligent routing
for file in src/**/*.py; do
  route_task "$file"
done
```

---

## Tips and Best Practices

1. **Use appropriate priorities**: Reserve 9-10 for truly urgent tasks
2. **Monitor agent health**: Check heartbeats regularly
3. **Clean up old tasks**: Run `./task-cli.sh cleanup` periodically
4. **Use messages for coordination**: Don't rely solely on task results
5. **Set realistic poll intervals**: Balance responsiveness with resource usage
6. **Log everything**: Logs are invaluable for debugging workflows
7. **Test workflows incrementally**: Start simple and add complexity

---

## Debugging Workflows

```bash
# Check what went wrong with a failed task
task_id="task-1234567890-5678"
./task-cli.sh status "$task_id" | jq '.[] | {status, error_message, retries}'

# View recent agent activity
sqlite3 /tmp/multi-agent-system/agents.db <<EOF
SELECT
  task_id,
  agent_id,
  action,
  datetime(timestamp, 'localtime') as time
FROM task_history
ORDER BY timestamp DESC
LIMIT 20;
EOF

# Check for stalled tasks
sqlite3 /tmp/multi-agent-system/agents.db <<EOF
SELECT
  id,
  task_type,
  assigned_to,
  (julianday('now') - julianday(started_at)) * 1440 as minutes_running
FROM tasks
WHERE status = 'in_progress'
  AND (julianday('now') - julianday(started_at)) * 1440 > 10;
EOF
```

---

These examples should give you a solid foundation for building your own multi-agent workflows!
