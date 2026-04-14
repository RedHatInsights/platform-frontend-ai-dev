#!/bin/bash
# PreToolUse hook for Bash command validation.
# Blocks dangerous commands that could be triggered by prompt injection
# from untrusted sources (Jira tickets, PR comments).
#
# Exit 0 = allow, JSON with permissionDecision "deny" = block.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Empty command — nothing to validate
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# --- NETWORK EXFILTRATION ---
# Block all network client tools. The bot should only make HTTP requests
# via MCP tools (mcp-atlassian, chrome-devtools, bot-memory).
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*(curl|wget|nc|ncat|netcat|socat|telnet|lynx|w3m|httpie|http)\b'; then
  deny "Network client commands (curl/wget/nc/etc.) are blocked. Use MCP tools for HTTP requests."
fi

# Block python/node network libraries used for exfiltration
if echo "$COMMAND" | grep -qiE 'python[23]?\s+.*-c\s+.*\b(urllib|requests|http\.client|socket)\b'; then
  deny "Python network library one-liners are blocked."
fi
if echo "$COMMAND" | grep -qiE 'node\s+.*-e\s+.*\b(fetch|http\.request|https\.request|net\.connect)\b'; then
  deny "Node.js network one-liners are blocked."
fi

# --- CREDENTIAL EXPOSURE ---
# Block commands that dump environment variables
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*printenv\b'; then
  deny "printenv is blocked — environment may contain secrets."
fi
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*env\s*$'; then
  deny "env (without arguments) is blocked — environment may contain secrets."
fi
# Block reading known credential files
if echo "$COMMAND" | grep -qiE '(cat|less|more|head|tail|bat|strings|xxd|od|hexdump)\s+.*(\.\benv\b|sa-key\.json|\.ssh/|\.gnupg/|\.aws/|\.kube/config|\.npmrc|\.pypirc)'; then
  deny "Reading credential/secret files is blocked."
fi
# Block echo/printf of secret env vars
if echo "$COMMAND" | grep -qiE '(echo|printf)\s+.*\$\{?(JIRA_API_TOKEN|SSH_PRIVATE_KEY|GPG_PRIVATE_KEY|GH_TOKEN|GOOGLE_SA_KEY|ANTHROPIC_API_KEY)'; then
  deny "Echoing secret environment variables is blocked."
fi
# Block gh auth commands that expose the PAT or require interactive login
if echo "$COMMAND" | grep -qiE 'gh\s+auth\s+(token|status\s+.*--show-token|refresh|login)'; then
  deny "gh auth token/refresh/login is blocked — interactive auth not available in container."
fi

# --- DESTRUCTIVE OPERATIONS ---
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*sudo\b'; then
  deny "sudo is blocked."
fi
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*su\s+-'; then
  deny "su is blocked."
fi
if echo "$COMMAND" | grep -qiE '\brm\s+(-[rR]f?|-f?[rR])\s+/(\s|$)'; then
  deny "Recursive deletion of root filesystem is blocked."
fi
if echo "$COMMAND" | grep -qiE '(^|[\|;`&(]|\$\()\s*(mkfs|fdisk|parted|dd\s+if=)\b'; then
  deny "Disk manipulation commands are blocked."
fi

# --- GIT SAFETY ---
# Block force push to default branches
if echo "$COMMAND" | grep -qiE 'git\s+push\s+.*--force.*\s+(main|master)\b'; then
  deny "Force push to main/master is blocked."
fi
if echo "$COMMAND" | grep -qiE 'git\s+push\s+.*\s+(main|master)\b.*--force'; then
  deny "Force push to main/master is blocked."
fi
# Block pushing directly to main/master (bot should only push bot/* branches)
if echo "$COMMAND" | grep -qiE 'git\s+push\s+\S+\s+(main|master)\s*$'; then
  deny "Direct push to main/master is blocked. Use bot/<TICKET-KEY> branches."
fi

# --- EVERYTHING ELSE ---
# Allow. The sandbox (Layer 3) handles filesystem and network enforcement
# at the OS level, so we don't need to catch everything here.
exit 0
