#!/bin/bash
# PreToolUse hook — block Read tool from accessing credential files.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

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

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Block reading SSH keys
if echo "$FILE_PATH" | grep -qE '\.ssh/'; then
  deny "BLOCKED: Reading SSH key files is not allowed."
fi

# Block reading GPG keys
if echo "$FILE_PATH" | grep -qE '\.gnupg/'; then
  deny "BLOCKED: Reading GPG key files is not allowed."
fi

# Block reading gh CLI config (contains PAT)
if echo "$FILE_PATH" | grep -qE '\.config/gh/'; then
  deny "BLOCKED: Reading GitHub CLI config is not allowed (contains auth token)."
fi

# Block reading GCP service account key
if echo "$FILE_PATH" | grep -qE '(^|/)sa-key\.json$'; then
  deny "BLOCKED: Reading GCP service account key is not allowed."
fi

# Block reading .env files
if echo "$FILE_PATH" | grep -qE '(^|/)\.env(\.|$)'; then
  deny "BLOCKED: Reading .env files is not allowed."
fi

# Block reading Jira credentials file
if echo "$FILE_PATH" | grep -qE '(^|/)\.jira-credentials$'; then
  deny "BLOCKED: Reading Jira credentials file is not allowed."
fi

# Block reading glab CLI config (contains token)
if echo "$FILE_PATH" | grep -qE '\.config/glab-cli/'; then
  deny "BLOCKED: Reading GitLab CLI config is not allowed (contains auth token)."
fi

# Block reading AWS credentials
if echo "$FILE_PATH" | grep -qE '\.aws/(credentials|config)'; then
  deny "BLOCKED: Reading AWS credential files is not allowed."
fi

# Block reading gcloud config
if echo "$FILE_PATH" | grep -qE '\.config/gcloud/'; then
  deny "BLOCKED: Reading gcloud config is not allowed."
fi

# All clean
exit 0
