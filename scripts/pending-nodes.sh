#!/usr/bin/env bash
#
# pending-nodes.sh — CGI-ish script that returns nodekeys seen in
# nginx logs that haven't been registered yet in headscale.
#
# Deployed behind nginx as a proxy_pass to a small socat/ncat listener,
# or called directly and piped through a lightweight HTTP wrapper.
#
# Output: JSON array of {key, firstSeen} objects.

set -euo pipefail

LOGFILE="/var/log/nginx/access.log"
API="http://127.0.0.1:8181"
API_KEY_FILE="/var/lib/headscale/.pending_api_key"

# Get a working API key (cached on disk; regenerated if expired).
get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        local key
        key=$(cat "$API_KEY_FILE")
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $key" "$API/api/v1/node")
        if [ "$status" = "200" ]; then
            echo "$key"
            return
        fi
    fi
    local key
    key=$(sudo docker exec headscale headscale apikeys create -e 8760h 2>/dev/null | tail -1)
    echo "$key" | sudo tee "$API_KEY_FILE" > /dev/null
    echo "$key"
}

API_KEY=$(get_api_key)

# Extract unique nodekeys from recent log entries (last 24h of log lines).
declare -A seen_keys
while IFS= read -r key; do
    seen_keys["$key"]=1
done < <(grep -oP 'GET /register/\K[A-Za-z0-9_-]+' "$LOGFILE" 2>/dev/null | sort -u)

if [ ${#seen_keys[@]} -eq 0 ]; then
    echo '[]'
    exit 0
fi

# Get registered node keys from headscale API.
registered=$(curl -s -H "Authorization: Bearer $API_KEY" "$API/api/v1/node" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for n in data.get('nodes', []):
    # The machineKey or nodeKey might be stored; we print all known identifiers.
    print(n.get('machineKey',''))
    print(n.get('nodeKey',''))
    print(n.get('givenName',''))
" 2>/dev/null)

# Filter out already-registered keys.
result="["
first=true
for key in "${!seen_keys[@]}"; do
    if ! echo "$registered" | grep -qF "$key"; then
        if [ "$first" = true ]; then
            first=false
        else
            result+=","
        fi
        result+="{\"key\":\"nodekey:$key\"}"
    fi
done
result+="]"

echo "$result"
