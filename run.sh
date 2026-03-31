#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOCK_FILE="$SCRIPT_DIR/.lock"

# Parse arguments
PRIMARY_LABEL=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --label) PRIMARY_LABEL="$2"; shift 2 ;;
    *) echo "Usage: $0 --label <primary-label>" >&2; exit 1 ;;
  esac
done

if [ -z "$PRIMARY_LABEL" ]; then
  echo "Error: --label is required (e.g. --label hcc-ai-framework)" >&2
  echo "Usage: $0 --label <primary-label>" >&2
  exit 1
fi

INTERVAL=$(jq -r '.polling.intervalSeconds' "$CONFIG")
IDLE_INTERVAL=$(jq -r '.polling.idleIntervalSeconds // 3600' "$CONFIG")
MAX_TURNS=$(jq -r '.claude.maxTurns' "$CONFIG")
MODEL=$(jq -r '.claude.model' "$CONFIG")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
  rm -f "$LOCK_FILE"
  log "Shutting down."
  exit 0
}
trap cleanup SIGINT SIGTERM

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  pid=$(cat "$LOCK_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    log "Another instance is running (PID $pid). Exiting."
    exit 1
  else
    log "Stale lock file found. Removing."
    rm -f "$LOCK_FILE"
  fi
fi
echo $$ > "$LOCK_FILE"

log "Dev bot started. Label: ${PRIMARY_LABEL}. Active interval: ${INTERVAL}s. Idle interval: ${IDLE_INTERVAL}s."

while true; do
  log "Running agent cycle..."

  cd "$SCRIPT_DIR"

  # Collect all persona MCP configs
  MCP_ARGS=()
  for MCP_FILE in "$SCRIPT_DIR"/personas/*/mcp.json; do
    [ -f "$MCP_FILE" ] && MCP_ARGS+=(--mcp-config "$MCP_FILE")
  done

  OUTPUT=$(claude --print \
    --verbose \
    --output-format stream-json \
    --max-turns "$MAX_TURNS" \
    --model "$MODEL" \
    "${MCP_ARGS[@]}" \
    --allowedTools "Edit" "Write" "Read" "Glob" "Grep" "Bash" "LSP" \
      "mcp__mcp-atlassian__jira_search" "mcp__mcp-atlassian__jira_get_issue" \
      "mcp__mcp-atlassian__jira_add_comment" "mcp__mcp-atlassian__jira_update_issue" \
      "mcp__mcp-atlassian__jira_get_transitions" "mcp__mcp-atlassian__jira_transition_issue" \
      "mcp__mcp-atlassian__jira_get_user_profile" \
      "mcp__mcp-atlassian__jira_download_attachments" \
      "mcp__hcc-patternfly-data-view__*" \
      "mcp__chrome-devtools__*" \
      "mcp__bot-memory__*" \
    -- "Your primary label is: ${PRIMARY_LABEL}. Follow the instructions in CLAUDE.md." 2>&1 | tee -a "$SCRIPT_DIR/bot.log") || {
    log "Agent run failed"
  }

  # Extract cost data from stream-json result and append to costs.jsonl
  RESULT_LINE=$(echo "$OUTPUT" | grep '"type":"result"' | tail -1)
  if [ -n "$RESULT_LINE" ]; then
    COST_ENTRY=$(echo "$RESULT_LINE" | python3 -c "
import json, sys
from datetime import datetime, timezone
r = json.loads(sys.stdin.readline())
u = r.get('usage', {})
m = r.get('modelUsage', {})
model_info = next(iter(m.values()), {})
entry = {
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'label': '${PRIMARY_LABEL}',
    'session_id': r.get('session_id', ''),
    'num_turns': r.get('num_turns', 0),
    'duration_ms': r.get('duration_ms', 0),
    'cost_usd': r.get('total_cost_usd', 0),
    'input_tokens': u.get('input_tokens', 0),
    'output_tokens': u.get('output_tokens', 0),
    'cache_read_tokens': u.get('cache_read_input_tokens', 0),
    'cache_write_tokens': u.get('cache_creation_input_tokens', 0),
    'model': next(iter(m.keys()), ''),
    'is_error': r.get('is_error', False),
    'no_work': 'NO_WORK_FOUND' in r.get('result', ''),
}
print(json.dumps(entry))
" 2>/dev/null)
    if [ -n "$COST_ENTRY" ]; then
      echo "$COST_ENTRY" >> "$SCRIPT_DIR/costs.jsonl"
    fi
  fi

  # Check if there was no work found — use longer idle interval
  if echo "$OUTPUT" | grep -q "NO_WORK_FOUND"; then
    log "No work found. Sleeping for ${IDLE_INTERVAL}s..."
    sleep "$IDLE_INTERVAL"
  else
    log "Cycle complete. Sleeping for ${INTERVAL}s..."
    sleep "$INTERVAL"
  fi
done
