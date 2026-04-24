---
name: triage
description: >
  Pre-triage data gathering for bot cycle. Fetches active tasks, PR/MR statuses,
  PR comments, Jira comments, capacity from memory server + gh/glab CLIs + Jira API.
  Groups by action bucket: MERGED, CI_FAIL, CONFLICTS, FEEDBACK, INTERRUPTED, CLEAN.
when_to_use: >
  Invoke at START of every bot cycle. Triggers on: "starting cycle", "triage",
  "task_list", "check tasks", "workflow loop", "priority 0", "resume work".
  Replaces manual task_list + jira_get_issue + gh pr view calls.
user-invocable: true
allowed-tools:
  - "Bash(python3 .claude/skills/triage/triage.py *)"
  - Read
  - mcp__bot-memory__task_update
  - mcp__bot-memory__bot_status_update
  - mcp__mcp-atlassian__jira_get_issue
  - mcp__mcp-atlassian__jira_add_comment
  - mcp__mcp-atlassian__jira_search
---

Run the triage script to gather task/PR/Jira data:

```bash
python3 .claude/skills/triage/triage.py 2>&1
```

The output is authoritative — do NOT re-fetch data already shown.
If `[jira unavailable]` for any ticket → use `jira_get_issue` MCP for those only.

Act on top bucket first. ONE item/cycle per CLAUDE.md rules.
Call `bot_status_update` w/ jira_key+repo before starting work.
