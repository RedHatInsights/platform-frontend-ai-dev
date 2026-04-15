#!/bin/bash
# Bot container entrypoint — decode secrets, start Chromium, launch bot.
set -e

# Decode SSH key
echo "$SSH_PRIVATE_KEY_B64" | base64 -d > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

# Import GPG key for commit signing
gpg --batch --import <(echo "$GPG_PRIVATE_KEY_B64" | base64 -d) 2>/dev/null
export GPG_SIGNING_KEY="$(gpg --list-secret-keys --keyid-format long 2>/dev/null | grep ed25519 | head -1 | awk '{print $2}' | cut -d/ -f2)"
git config --global user.signingkey "$GPG_SIGNING_KEY"

# Decode GCP service account key
echo "$GOOGLE_SA_KEY_B64" | base64 -d > /home/botuser/sa-key.json

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

# Start headless Chromium in background (Playwright-installed binary)
CHROME_BIN=$(find "$PLAYWRIGHT_BROWSERS_PATH" -name chrome -type f | head -1)
"$CHROME_BIN" \
    --headless --no-sandbox --disable-gpu \
    --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 \
    --ignore-certificate-errors \
    --host-resolver-rules='MAP consent.trustarc.com 127.0.0.1' \
    --no-first-run --disable-sync --disable-extensions --disable-popup-blocking &

# Wait for Chromium to be ready
until curl -s http://127.0.0.1:9222/json/version > /dev/null 2>&1; do sleep 1; done

echo "Keys loaded. Chromium started. Starting bot with label: ${BOT_LABEL}"
exec uv run dev-bot --label "$BOT_LABEL"
