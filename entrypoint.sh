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

# Git credential helpers for HTTPS auth (replaces SSH keys)
# GitHub: gh CLI acts as credential helper (set up below)
# GitLab: custom helper script injects token
if [ -n "${GITLAB_TOKEN:-}" ]; then
    cat > /home/botuser/.git-credential-gitlab <<CREDEOF
#!/bin/bash
echo "username=${GL_USERNAME}"
echo "password=${GITLAB_TOKEN}"
CREDEOF
    chmod 700 /home/botuser/.git-credential-gitlab
    git config --global credential.https://gitlab.cee.redhat.com.helper "/home/botuser/.git-credential-gitlab"
fi

# Write SSO credentials file for stage auth (chrome-devtools)
if [ -n "${SSO_USERNAME:-}" ] && [ -n "${SSO_PASSWORD:-}" ]; then
    cat > /home/botuser/app/.credentials <<EOF
{"sso": {"username": "${SSO_USERNAME}", "password": "${SSO_PASSWORD}"}}
EOF
    chmod 600 /home/botuser/app/.credentials
    unset SSO_USERNAME SSO_PASSWORD
fi

# Import GPG keys for commit signing (may contain keys for both platforms)
if [ -n "${GPG_PRIVATE_KEY_B64:-}" ]; then
    gpg --batch --import <(decode_or_raw "$GPG_PRIVATE_KEY_B64") 2>/dev/null
fi

# Per-platform git identity via includeIf (git 2.36+)
# Each platform gets its own name, email, and GPG signing key.
GH_GPG_KEY="$(gpg --list-secret-keys --keyid-format long "${GH_USER_EMAIL}" 2>/dev/null | grep -oP '(?<=/)[A-F0-9]{16}' | head -1)"
GL_GPG_KEY="$(gpg --list-secret-keys --keyid-format long "${GL_USER_EMAIL}" 2>/dev/null | grep -oP '(?<=/)[A-F0-9]{16}' | head -1)"

cat > /home/botuser/.gitconfig-gh <<EOF
[user]
	name = ${GH_USER_NAME}
	email = ${GH_USER_EMAIL}
	signingkey = ${GH_GPG_KEY}
EOF

cat > /home/botuser/.gitconfig-gl <<EOF
[user]
	name = ${GL_USER_NAME}
	email = ${GL_USER_EMAIL}
	signingkey = ${GL_GPG_KEY}
EOF

git config --global 'includeIf.hasconfig:remote.*.url:https://github.com/**.path' /home/botuser/.gitconfig-gh
git config --global 'includeIf.hasconfig:remote.*.url:https://gitlab.cee.redhat.com/**.path' /home/botuser/.gitconfig-gl

# Verify per-platform identity + GPG signing (warn-only, never fatal)
verify_platform_signing() {
    local platform="$1" url="$2" expected_email="$3"
    local tmpdir
    tmpdir=$(mktemp -d)
    git init -q "$tmpdir"
    git -C "$tmpdir" remote add origin "$url"
    local resolved_email resolved_key
    resolved_email=$(git -C "$tmpdir" config user.email)
    resolved_key=$(git -C "$tmpdir" config user.signingkey)
    rm -rf "$tmpdir"

    if [ -z "$resolved_email" ]; then
        echo "WARNING: ${platform} — includeIf did not resolve identity"
        return
    fi
    if [ "$resolved_email" != "$expected_email" ]; then
        echo "WARNING: ${platform} — email mismatch: got ${resolved_email}, expected ${expected_email}"
        return
    fi
    if [ -z "$resolved_key" ]; then
        echo "WARNING: ${platform} — no GPG signing key resolved"
        return
    fi
    if echo "test" | gpg --local-user "$resolved_key" --sign > /dev/null 2>&1; then
        echo "${platform} identity + GPG signing OK (${resolved_email})"
    else
        echo "WARNING: ${platform} — GPG key cannot sign (missing or expired)"
    fi
}
verify_platform_signing "GitHub" "https://github.com/test/repo.git" "${GH_USER_EMAIL}"
verify_platform_signing "GitLab" "https://gitlab.cee.redhat.com/test/repo.git" "${GL_USER_EMAIL}"

# Decode GCP service account key
if [ -n "${GOOGLE_SA_KEY_B64:-}" ]; then
    decode_or_raw "$GOOGLE_SA_KEY_B64" > /home/botuser/sa-key.json
fi

# Write Jira credentials file for triage skill (same pattern as gh/glab config files)
if [ -n "${JIRA_URL:-}" ] && [ -n "${JIRA_USERNAME:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
    cat > ~/.jira-credentials <<EOF
{"url": "${JIRA_URL}", "username": "${JIRA_USERNAME}", "token": "${JIRA_API_TOKEN}"}
EOF
    chmod 600 ~/.jira-credentials
fi

# Point MCP config to the memory server
sed -i "s|http://localhost:8080/mcp|${BOT_MEMORY_URL}|" .mcp.json

# Configure gh CLI auth (HTTPS + credential helper for git)
mkdir -p ~/.config/gh
cat > ~/.config/gh/hosts.yml <<EOF
github.com:
    oauth_token: ${GH_TOKEN}
    user: ${GH_USERNAME}
    git_protocol: https
EOF
gh auth setup-git 2>/dev/null || true

# Remove token from env — gh uses the config file from now on
unset GH_TOKEN

# Configure glab CLI auth (GitLab)
if [ -n "${GITLAB_TOKEN:-}" ]; then
    mkdir -p ~/.config/glab-cli
    cat > ~/.config/glab-cli/config.yml <<EOF
git_protocol: https
check_update: false
no_prompt: true
host: gitlab.cee.redhat.com
hosts:
    gitlab.cee.redhat.com:
        token: ${GITLAB_TOKEN}
        api_protocol: https
        api_host: gitlab.cee.redhat.com
        git_protocol: https
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

# --- Wait for dependent services (OpenShift deploys all pods concurrently) ---
wait_for_http() {
    local name="$1" url="$2" timeout="${3:-120}"
    echo "Waiting for ${name} at ${url} (timeout=${timeout}s)..."
    local elapsed=0
    until curl -sf --noproxy '*' "$url" > /dev/null 2>&1; do
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "FATAL: ${name} not ready after ${timeout}s" >&2
            exit 1
        fi
        sleep 2
    done
    echo "${name} is ready."
}

wait_for_tcp() {
    local name="$1" host="$2" port="$3" timeout="${4:-120}"
    echo "Waiting for ${name} at ${host}:${port} (timeout=${timeout}s)..."
    local elapsed=0
    until bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; do
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "FATAL: ${name} not ready after ${timeout}s" >&2
            exit 1
        fi
        sleep 2
    done
    echo "${name} is ready."
}

# Proxy must be up before Chromium (which routes through it)
# Uses TCP check — Squid doesn't serve HTTP on its proxy port
# TODO: update template to replace BOT_PROXY_HEALTH_URL with PROXY_HOST/PROXY_PORT
if [ -n "${PROXY_HOST:-}" ]; then
    wait_for_tcp "proxy" "$PROXY_HOST" "${PROXY_PORT:-3128}" "${BOT_PROXY_HEALTH_TIMEOUT:-60}"
fi

# Memory server must be up before the bot connects via MCP
if [ -n "${BOT_MEMORY_HEALTH_URL:-}" ]; then
    wait_for_http "memory-server" "$BOT_MEMORY_HEALTH_URL" "${BOT_MEMORY_HEALTH_TIMEOUT:-120}"
fi

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

echo "Credentials configured. Chromium started. Starting bot with label: ${BOT_LABEL}"
exec uv run dev-bot --label "$BOT_LABEL"
