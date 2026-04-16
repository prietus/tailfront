import SwiftUI

struct NodesView: View {
    @EnvironmentObject var servers: ServerStore
    @EnvironmentObject var nodeMonitor: NodeMonitor
    let server: Server

    @State private var nodes: [HSNode] = []
    @State private var loading = false
    @State private var error: String?
    @State private var registerItem: RegisterItem?

    private struct RegisterItem: Identifiable {
        let id = UUID()
        let key: String
    }

    private var pending: [HSPendingNode] {
        nodeMonitor.pendingByServer[server.id] ?? []
    }

    var body: some View {
        List {
            if !pending.isEmpty {
                Section("Pending Registration") {
                    ForEach(pending) { node in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "laptopcomputer.and.arrow.down")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(node.device ?? "Unknown device")
                                        .font(.headline)
                                    if let ip = node.ip {
                                        Text(ip)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            HStack {
                                Spacer()
                                Button("Dismiss") {
                                    Task { await dismiss(node) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button("Register") {
                                    registerItem = RegisterItem(key: node.key)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if loading && nodes.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            ForEach(nodes) { node in
                NavigationLink {
                    NodeDetailView(server: server, onChanged: { Task { await load() } }, node: node)
                } label: {
                    NodeRow(node: node)
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .refreshable { await load() }
        .task(id: server.id) { await load() }
        .overlay {
            if !loading && nodes.isEmpty && pending.isEmpty && error == nil {
                ContentUnavailableView {
                    Label("No nodes", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text("Nodes will appear here after they register with Headscale.")
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { registerItem = RegisterItem(key: "") } label: {
                    Label("Register Node", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { Task { await load() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .sheet(item: $registerItem) { item in
            RegisterNodeView(server: server, prefillKey: item.key) { _ in
                Task {
                    await load()
                    await nodeMonitor.pollAll()
                }
            }
        }
    }

    private func dismiss(_ node: HSPendingNode) async {
        guard let apiKey = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            try await client.denyPendingNode(key: node.key)
            await nodeMonitor.pollAll()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load() async {
        guard let key = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        loading = true
        defer { loading = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            nodes = try await client.nodes().sorted { lhs, rhs in
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct NodeRow: View {
    let node: HSNode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(node.isOnline ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(node.displayName).font(.headline)
                    if let user = node.user?.name {
                        Text(user)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let ip = node.primaryIP {
                    Text(ip)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !node.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(node.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(node.isOnline ? "online" : "offline")
                        .font(.caption2)
                        .foregroundStyle(node.isOnline ? .green : .secondary)
                    if let seen = node.lastSeen {
                        Text("· last seen \(seen.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
