#!/usr/bin/env bash
#
# headscale-notify.sh — watches headscale Docker logs for new node
# registration attempts and sends a push notification via ntfy.sh.
#
# Install as a systemd service on the headscale host:
#   sudo cp headscale-notify.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/headscale-notify.sh
#   sudo cp headscale-notify.service /etc/systemd/system/
#   sudo systemctl enable --now headscale-notify
#
# Subscribe to notifications on your phone/mac:
#   ntfy app → subscribe to the topic below
#
NTFY_TOPIC="${NTFY_TOPIC:-tailfront-al-andal}"
NTFY_URL="https://ntfy.sh/${NTFY_TOPIC}"
CONTAINER="${HEADSCALE_CONTAINER:-headscale}"

echo "Watching ${CONTAINER} logs → notifications to ${NTFY_URL}"

# Tail docker logs (--follow --since=now) and look for registration events.
# Headscale 0.26 logs these patterns when a new node tries to register:
#   - "node not found" (node key not in DB)
#   - "register" in various contexts
#   - "new node" / "machine registration"
sudo docker logs --follow --since "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${CONTAINER}" 2>&1 \
  | while IFS= read -r line; do
    # Node connected (already registered)
    if echo "$line" | grep -qiE 'node has connected'; then
        node=$(echo "$line" | grep -oP 'node=\K\S+' || echo "unknown")
        echo "[connect] ${node}"
        continue
    fi

    # New node registration attempt (not yet registered)
    if echo "$line" | grep -qiE 'register|not found.*node|new.*machine|machine.*register|node.*register'; then
        echo "[REGISTER] $line"
        curl -s \
            -H "Title: New node wants to join" \
            -H "Priority: high" \
            -H "Tags: computer,key" \
            -H "Actions: view, Open Tailfront, tailfront://" \
            -d "A new Tailscale node is trying to register with Headscale.

${line}" \
            "${NTFY_URL}" > /dev/null
    fi
done
