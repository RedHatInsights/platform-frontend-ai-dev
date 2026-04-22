#!/bin/bash
# Bot container entrypoint — decode secrets, start Chromium, launch bot.
set -e

# --- Verify required CLI tools ---
MISSING=""
for tool in gh glab git gpg; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING="$MISSING $tool"
    fi
done
if [ -n "$MISSING" ]; then
    echo "FATAL: Missing required tools:$MISSING" >&2
    echo "Rebuild with: docker compose build --no-cache bot" >&2
    exit 1
fi

# Kubernetes secretKeyRef auto-decodes base64, so secrets arrive as raw values
# in OpenShift. Local docker-compose still passes them base64-encoded via .env.
# This helper handles both: values starting with "-----" or "{" are not valid
# base64 and are the only two raw formats we expect, so write them as-is.
# Everything else is base64-decoded.
decode_or_raw() {
    case "$1" in
        -----*|"{"*) printf '%s' "$1" ;;
        *) echo "$1" | base64 -d 2>/dev/null ;;
    esac
}

# Decode SSH keys (separate keys for GitHub and GitLab)
if [ -n "${SSH_PRIVATE_KEY_B64:-}" ]; then
    decode_or_raw "$SSH_PRIVATE_KEY_B64" > ~/.ssh/id_gh
    chmod 600 ~/.ssh/id_gh
    unset SSH_PRIVATE_KEY_B64
fi

if [ -n "${GITLAB_SSH_KEY_B64:-}" ]; then
    decode_or_raw "$GITLAB_SSH_KEY_B64" > ~/.ssh/id_gl
    chmod 600 ~/.ssh/id_gl
    unset GITLAB_SSH_KEY_B64
fi

# Generate SSH config — PROXY_HOST defaults to "proxy" (matches docker-compose service name)
PROXY_HOST="${PROXY_HOST:-proxy}"
cat > ~/.ssh/config <<SSHEOF
Host github.com
  HostName github.com
  User git
  IdentityFile /home/botuser/.ssh/id_gh
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyCommand socat - PROXY:${PROXY_HOST}:%h:%p,proxyport=3128

Host gitlab.cee.redhat.com
  IdentityFile /home/botuser/.ssh/id_gl
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyCommand socat - PROXY:${PROXY_HOST}:%h:%p,proxyport=3128
SSHEOF
chmod 600 ~/.ssh/config

# Write SSO credentials file for stage auth (chrome-devtools)
if [ -n "${SSO_USERNAME:-}" ] && [ -n "${SSO_PASSWORD:-}" ]; then
    cat > /home/botuser/app/.credentials <<EOF
{"sso": {"username": "${SSO_USERNAME}", "password": "${SSO_PASSWORD}"}}
EOF
    chmod 600 /home/botuser/app/.credentials
    unset SSO_USERNAME SSO_PASSWORD
fi

# Import GPG key for commit signing
if [ -n "${GPG_PRIVATE_KEY_B64:-}" ]; then
    gpg --batch --import <(decode_or_raw "$GPG_PRIVATE_KEY_B64") 2>/dev/null
fi
export GPG_SIGNING_KEY="$(gpg --list-secret-keys --keyid-format long 2>/dev/null | grep ed25519 | head -1 | awk '{print $2}' | cut -d/ -f2)"
git config --global user.signingkey "$GPG_SIGNING_KEY"

# Decode GCP service account key
if [ -n "${GOOGLE_SA_KEY_B64:-}" ]; then
    decode_or_raw "$GOOGLE_SA_KEY_B64" > /home/botuser/sa-key.json
fi

# Point MCP config to the memory server
sed -i "s|http://localhost:8080/sse|${BOT_MEMORY_URL}|" .mcp.json

# Configure gh CLI auth
mkdir -p ~/.config/gh
cat > ~/.config/gh/hosts.yml <<EOF
github.com:
    oauth_token: ${GH_TOKEN}
    user: platex-rehor-bot
    git_protocol: ssh
EOF

# Remove token from env — gh uses the config file from now on
unset GH_TOKEN

# Configure glab CLI auth (GitLab)
if [ -n "${GITLAB_TOKEN:-}" ]; then
    mkdir -p ~/.config/glab-cli
    cat > ~/.config/glab-cli/config.yml <<EOF
git_protocol: ssh
check_update: false
no_prompt: true
host: gitlab.cee.redhat.com
hosts:
    gitlab.cee.redhat.com:
        token: ${GITLAB_TOKEN}
        api_protocol: https
        api_host: gitlab.cee.redhat.com
        git_protocol: ssh
        skip_tls_verify: true
EOF
    chmod 600 ~/.config/glab-cli/config.yml
    unset GITLAB_TOKEN
fi

# --- Verify auth ---
echo "Verifying GitHub auth..."
gh auth status 2>&1 | head -3 || { echo "WARNING: gh auth failed"; }
echo "Verifying GitLab auth..."
glab auth status --hostname gitlab.cee.redhat.com 2>&1 | head -3 || { echo "WARNING: glab auth failed"; }

# Start headless Chromium in background (Playwright-installed binary)
CHROME_BIN=$(find "$PLAYWRIGHT_BROWSERS_PATH" -name chrome -type f | head -1)
"$CHROME_BIN" \
    --headless --no-sandbox --disable-gpu \
    --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 \
    --remote-allow-origins=* \
    --ignore-certificate-errors \
    --host-resolver-rules='MAP consent.trustarc.com 127.0.0.1' \
    --proxy-server="${HTTPS_PROXY:-http://proxy:3128}" \
    --proxy-bypass-list='*.foo.redhat.com;localhost;127.0.0.1' \
    --no-first-run --disable-sync --disable-extensions --disable-popup-blocking &

# Wait for Chromium to be ready
until curl -s http://127.0.0.1:9222/json/version > /dev/null 2>&1; do sleep 1; done

echo "Keys loaded. Chromium started. Starting bot with label: ${BOT_LABEL}"
exec uv run dev-bot --label "$BOT_LABEL"
