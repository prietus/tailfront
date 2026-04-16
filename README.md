# Tailfront

A native SwiftUI GUI for managing a self-hosted [Headscale](https://github.com/juanfont/headscale) server. Runs on both iOS and macOS from a single codebase.

## Features

- **Multiple servers** — manage several Headscale instances from the same app, with API keys stored in the system keychain.
- **Users** — list, create, rename, delete.
- **Nodes** — list with online status, detail view, rename, move to another user, edit tags, force re-auth, delete.
- **Subnet routes** — approve or revoke routes advertised by each node directly from its detail view.
- **Pending registrations** — a "Pending Registration" section surfaces nodes that have contacted the server but are not yet registered, with one-tap Register / Dismiss. Optional local notifications fire when a new device appears. Requires a small server-side helper (see below).
- **Pre-auth keys** — list, create (reusable / ephemeral / with ACL tags / custom expiry), expire.
- **Policy editor** — two modes:
  - **Structure** — collapsible, read-only browser of groups, tag owners, hosts, ACLs, SSH rules and auto-approvers with color-coded chips. Swipe or right-click an ACL to delete it; the HuJSON comments and formatting in the rest of the file are preserved.
  - **Text** — raw HuJSON editor with monospaced font.

## Requirements

- macOS 14+ / iOS 17+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A running Headscale server (v0.26+) reachable over HTTPS with a valid API key.

## Build

```sh
xcodegen
open Tailfront.xcodeproj
```

Then select the iOS or macOS scheme and run.

## Configuration

On first launch, add a server:

1. Base URL of your Headscale instance (e.g. `https://headscale.example.com`).
2. A Headscale API key. You can generate one with:
   ```sh
   docker exec headscale headscale apikeys create -e 8760h
   ```

The key is stored in the Keychain and used for all subsequent requests to that server.

## Optional: pending-node helper

Headscale does not expose an API for "nodes that tried to register but are not yet approved". The repo ships a small Python sidecar that parses nginx access logs to surface those attempts:

- `scripts/pending-nodes.py` — HTTP service on `127.0.0.1:8182` exposing `GET /pending` and `DELETE /pending/{key}`.
- Proxy it through your Headscale nginx under `/tailfront/` with the `Authorization` header forwarded.

Without this helper the "Pending Registration" section simply stays empty; everything else in the app works normally.

## License

[MIT](LICENSE)
