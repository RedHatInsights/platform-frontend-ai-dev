#!/bin/bash
set -e

# Configure gh auth (token from env)
mkdir -p ~/.config/gh
cat > ~/.config/gh/hosts.yml <<EOF
github.com:
    oauth_token: ${GH_TOKEN}
    user: ${GH_USERNAME:-}
    git_protocol: https
EOF
chmod 600 ~/.config/gh/hosts.yml

# Configure glab auth (token from env)
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
fi

# Import GPG keys for commit signing (keys live in proxy, not bot)
if [ -n "${GPG_PRIVATE_KEY_B64:-}" ]; then
    case "$GPG_PRIVATE_KEY_B64" in
        -----*|"{"*) printf '%s' "$GPG_PRIVATE_KEY_B64" | gpg --batch --import 2>/dev/null ;;
        *) echo "$GPG_PRIVATE_KEY_B64" | base64 -d | gpg --batch --import 2>/dev/null ;;
    esac
    echo "GPG keys imported in proxy container"
fi

# Start Squid in background
squid -N -f /etc/squid/squid.conf &
SQUID_PID=$!

# Start executor server in background
# EXECUTOR_LISTEN controls transport: unix:///path (local dev) or :9090 (k8s)
/usr/local/bin/executor-server \
    --listen "${EXECUTOR_LISTEN:-unix:///var/run/devbot/executor.sock}" \
    --gh-path /usr/local/bin/gh-real \
    --glab-path /usr/local/bin/glab-real \
    --gpg-path /usr/bin/gpg &
EXECUTOR_PID=$!

cleanup() { kill $SQUID_PID $EXECUTOR_PID 2>/dev/null; }
trap cleanup EXIT TERM INT

wait -n $SQUID_PID $EXECUTOR_PID
exit $?
