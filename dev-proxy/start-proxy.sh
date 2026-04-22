#!/bin/bash
# Start the HCC dev proxy (Caddy-based) for UI verification.
# Generates Caddy route config from a routes.json file and starts Caddy.
#
# Env vars:
#   ROUTES_JSON_PATH  — path to routes.json (required)
#   HCC_ENV           — environment name (default: stage)
#   PROXY_PORT        — listen port (default: 1337)
#   HCC_ENV_URL       — upstream HCC URL (default: https://console.stage.redhat.com)

set -euo pipefail

ROUTES_JSON_PATH="${ROUTES_JSON_PATH:?ROUTES_JSON_PATH must be set}"
CUSTOM_ROUTES="${LOCAL_CUSTOM_ROUTES_PATH:-}"

export HCC_ENV="${HCC_ENV:-stage}"
export PROXY_PORT="${PROXY_PORT:-1337}"
export HCC_ENV_URL="${HCC_ENV_URL:-https://console.stage.redhat.com}"

if [ -f "$ROUTES_JSON_PATH" ] && [ -n "$CUSTOM_ROUTES" ] && [ -f "$CUSTOM_ROUTES" ]; then
  JSON_INPUT=$(jq -s '.[0] * .[1]' "$ROUTES_JSON_PATH" "$CUSTOM_ROUTES")
elif [ -f "$ROUTES_JSON_PATH" ]; then
  JSON_INPUT=$(cat "$ROUTES_JSON_PATH")
else
  echo "No routes config at $ROUTES_JSON_PATH" >&2
  exit 1
fi

output=$(
  echo "$JSON_INPUT" | jq -r 'to_entries[] | [.key, .value.url, (
    if .key | startswith("/api/") then
        if .value."rh-identity-headers" == false then
            false
        else
            true
        end
    else
        .value."rh-identity-headers" // false
    end
  ), .value."is_chrome"] | @tsv' |
    while IFS=$'\t' read -r path url rh_identity is_chrome; do
      if [ "$is_chrome" = "true" ]; then
        printf "\thandle @html_fallback {\n"
        printf "\t\trewrite * /apps/chrome/index.html\n"
        printf "\t\treverse_proxy %s {\n" "$url"
        printf "\t\t\theader_up Host {http.reverse_proxy.upstream.hostport}\n"
        printf '\t\t\theader_up Cache-Control "no-cache, no-store, must-revalidate"\n'
        printf "\t\t}\n"
        printf "\t}\n\n"
      fi

      printf "\thandle %s {\n" "$path"
      printf "\t\treverse_proxy %s {\n" "$url"
      printf "\t\t\theader_up Host {http.reverse_proxy.upstream.hostport}\n"
      printf '\t\t\theader_up Cache-Control "no-cache, no-store, must-revalidate"\n'
      printf "\t\t}\n"
      if [ "$rh_identity" = "true" ]; then
        printf "\n\t\trh_identity_transform\n"
      fi
      printf "\t}\n\n"
    done
)

export LOCAL_ROUTES="$output"
exec /usr/local/bin/caddy run --config /etc/caddy/Caddyfile
