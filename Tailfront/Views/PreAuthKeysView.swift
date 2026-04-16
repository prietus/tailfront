import SwiftUI

struct PreAuthKeysView: View {
    @EnvironmentObject var servers: ServerStore
    let server: Server

    @State private var users: [HSUser] = []
    @State private var selectedUserID: String?
    @State private var keys: [HSPreAuthKey] = []
    @State private var showActiveOnly = true
    @State private var loading = false
    @State private var error: String?
    @State private var showingCreate = false
    @State private var justCopiedID: String?

    private var filteredKeys: [HSPreAuthKey] {
        let base = showActiveOnly ? keys.filter(\.isActive) : keys
        return base.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if users.count > 1 {
                Section {
                    Picker("User", selection: $selectedUserID) {
                        ForEach(users) { user in
                            Text(user.name).tag(Optional(user.id))
                        }
                    }
                }
            }

            Section {
                Toggle("Active only", isOn: $showActiveOnly)
            }

            if loading && keys.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            ForEach(filteredKeys) { key in
                PreAuthKeyRow(key: key, justCopied: justCopiedID == key.id) {
                    Clipboard.copy(key.key)
                    justCopiedID = key.id
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if justCopiedID == key.id { justCopiedID = nil }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if key.isActive {
                        Button("Expire", role: .destructive) {
                            Task { await expire(key) }
                        }
                    }
                }
                .contextMenu {
                    Button("Copy key") { Clipboard.copy(key.key) }
                    if key.isActive {
                        Button("Expire", role: .destructive) {
                            Task { await expire(key) }
                        }
                    }
                }
            }

            if !loading && filteredKeys.isEmpty && error == nil {
                Text(showActiveOnly ? "No active keys" : "No keys")
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .refreshable { await reload() }
        .task(id: server.id) { await reload() }
        .onChange(of: selectedUserID) { _, _ in
            Task { await loadKeys() }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem {
                Button { showingCreate = true } label: {
                    Label("New Key", systemImage: "plus")
                }
                .disabled(selectedUserID == nil)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingCreate) {
            if let userID = selectedUserID {
                CreatePreAuthKeyView(server: server, userID: userID) { newKey in
                    keys.insert(newKey, at: 0)
                }
            }
        }
    }

    private func reload() async {
        guard let key = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        loading = true
        defer { loading = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            users = try await client.users()
            if selectedUserID == nil || !users.contains(where: { $0.id == selectedUserID }) {
                selectedUserID = users.first?.id
            }
            await loadKeys(using: client)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadKeys(using client: HeadscaleClient? = nil) async {
        guard let userID = selectedUserID else { keys = []; return }
        guard let key = servers.apiKey(for: server) else { return }
        let c = client ?? HeadscaleClient(baseURL: server.baseURL, apiKey: key)
        do {
            keys = try await c.preAuthKeys(userID: userID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func expire(_ key: HSPreAuthKey) async {
        guard let apiKey = servers.apiKey(for: server), let userID = selectedUserID else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            try await client.expirePreAuthKey(userID: userID, key: key.key)
            await loadKeys(using: client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PreAuthKeyRow: View {
    let key: HSPreAuthKey
    let justCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.key)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(justCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                if key.reusable { Badge(text: "reusable", color: .blue) }
                if key.ephemeral { Badge(text: "ephemeral", color: .purple) }
                if key.used { Badge(text: "used", color: .secondary) }
                if key.isExpired { Badge(text: "expired", color: .red) }
                ForEach(key.aclTags ?? [], id: \.self) { tag in
                    Badge(text: tag, color: .accentColor)
                }
            }

            if let exp = key.expiration {
                Text("expires \(exp.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
