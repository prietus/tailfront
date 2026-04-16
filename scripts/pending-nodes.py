#!/usr/bin/env python3
"""
Tiny HTTP service that returns nodekeys seen in nginx access logs
that are not yet registered in headscale.

Listens on 127.0.0.1:8182, proxied by nginx at /tailfront/pending.
"""

import http.server
import json
import re
import subprocess
import urllib.request
from pathlib import Path

PORT = 8182
LOGFILE = "/var/log/nginx/access.log"
API = "http://127.0.0.1:8181"
KEY_FILE = Path("/var/lib/headscale/.tailfront_api_key")
DISMISSED_FILE = Path("/var/lib/headscale/.tailfront_dismissed")

REGISTER_RE = re.compile(r"GET /register/([A-Za-z0-9_-]+)")
LOG_LINE_RE = re.compile(
    r'^(\S+) .+ \[([^\]]+)\] "GET /register/([A-Za-z0-9_-]+)[^"]*" \d+ \d+ "[^"]*" "([^"]*)"'
)


def get_api_key() -> str:
    """Return a valid Headscale API key, creating one if needed."""
    if KEY_FILE.exists():
        key = KEY_FILE.read_text().strip()
        try:
            req = urllib.request.Request(
                f"{API}/api/v1/node",
                headers={"Authorization": f"Bearer {key}"},
            )
            with urllib.request.urlopen(req, timeout=5) as r:
                if r.status == 200:
                    return key
        except Exception:
            pass

    out = subprocess.check_output(
        ["docker", "exec", "headscale", "headscale", "apikeys", "create", "-e", "8760h"],
        stderr=subprocess.DEVNULL,
    )
    key = out.decode().strip().split("\n")[-1]
    KEY_FILE.write_text(key)
    return key


def get_registered_keys(api_key: str) -> set[str]:
    """Fetch all known node keys from headscale."""
    req = urllib.request.Request(
        f"{API}/api/v1/node",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    keys = set()
    for node in data.get("nodes", []):
        for field in ("machineKey", "nodeKey", "givenName", "name"):
            v = node.get(field, "")
            if v:
                # Strip prefix like "nodekey:" if present
                keys.add(v.split(":")[-1] if ":" in v else v)
    return keys


def load_dismissed() -> set[str]:
    """Load dismissed/registered keys from disk."""
    if DISMISSED_FILE.exists():
        return set(DISMISSED_FILE.read_text().strip().splitlines())
    return set()


def save_dismissed(dismissed: set[str]):
    DISMISSED_FILE.write_text("\n".join(sorted(dismissed)) + "\n")


def parse_user_agent(ua: str) -> str:
    """Extract a human-friendly device description from a user agent string."""
    # Tailscale client UA
    if "Tailscale" in ua:
        return ua.split("/")[0].strip() if "/" in ua else ua

    # Browser UAs — extract device/OS
    if "iPad" in ua:
        m = re.search(r"CPU OS (\S+)", ua)
        ver = m.group(1).replace("_", ".") if m else ""
        return f"iPad (iOS {ver})" if ver else "iPad"
    if "iPhone" in ua:
        m = re.search(r"CPU iPhone OS (\S+)", ua)
        ver = m.group(1).replace("_", ".") if m else ""
        return f"iPhone (iOS {ver})" if ver else "iPhone"
    if "Macintosh" in ua:
        m = re.search(r"Mac OS X ([\d_]+)", ua)
        ver = m.group(1).replace("_", ".") if m else ""
        return f"Mac (macOS {ver})" if ver else "Mac"
    if "Android" in ua:
        m = re.search(r"Android ([\d.]+)", ua)
        ver = m.group(1) if m else ""
        return f"Android {ver}" if ver else "Android"
    if "Windows" in ua:
        return "Windows"
    if "Linux" in ua:
        return "Linux"
    return ua[:60] if ua else "Unknown"


def get_pending() -> list[dict]:
    """Return nodekeys from nginx logs not yet registered or denied."""
    try:
        log_lines = Path(LOGFILE).read_text().splitlines()
    except OSError:
        return []

    # Parse log lines to get key → {ip, device, timestamp} (last seen wins).
    key_info: dict[str, dict] = {}
    for line in log_lines:
        m = LOG_LINE_RE.match(line)
        if m:
            ip, timestamp, key, ua = m.groups()
            key_info[key] = {
                "ip": ip,
                "device": parse_user_agent(ua),
                "seen": timestamp,
            }

    if not key_info:
        return []

    dismissed = load_dismissed()

    pending = []
    for key, info in key_info.items():
        if key not in dismissed:
            pending.append({
                "key": f"nodekey:{key}",
                "ip": info["ip"],
                "device": info["device"],
            })
    return pending


def verify_token(auth_header: str) -> bool:
    """Verify the Bearer token is valid against headscale."""
    if not auth_header or not auth_header.startswith("Bearer "):
        return False
    try:
        req = urllib.request.Request(
            f"{API}/api/v1/node",
            headers={"Authorization": auth_header},
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status == 200
    except Exception:
        return False


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/pending":
            self.send_error(404)
            return

        auth = self.headers.get("Authorization", "")
        if not verify_token(auth):
            self.send_error(401, "Unauthorized")
            return

        try:
            result = get_pending()
            body = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            body = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

    def do_DELETE(self):
        if not self.path.startswith("/pending/"):
            self.send_error(404)
            return

        auth = self.headers.get("Authorization", "")
        if not verify_token(auth):
            self.send_error(401, "Unauthorized")
            return

        # Extract key: /pending/nodekey:abc123 or /pending/abc123
        from urllib.parse import unquote
        raw_key = unquote(self.path[len("/pending/"):])
        key = raw_key.replace("nodekey:", "")

        dismissed = load_dismissed()
        dismissed.add(key)
        save_dismissed(dismissed)

        self.send_response(204)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # silent


if __name__ == "__main__":
    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Listening on 127.0.0.1:{PORT}")
    server.serve_forever()
