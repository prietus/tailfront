import SwiftUI

struct UsersView: View {
    @EnvironmentObject var servers: ServerStore
    let server: Server

    @State private var users: [HSUser] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showingCreate = false
    @State private var renaming: HSUser?
    @State private var renameText = ""
    @State private var deleting: HSUser?

    var body: some View {
        List {
            if loading && users.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name).font(.headline)
                    if let dn = user.displayName, !dn.isEmpty {
                        Text(dn).font(.caption).foregroundStyle(.secondary)
                    }
                    if let email = user.email, !email.isEmpty {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("id: \(user.id)").font(.caption2).foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { deleting = user }
                    Button("Rename") {
                        renameText = user.name
                        renaming = user
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button("Rename") {
                        renameText = user.name
                        renaming = user
                    }
                    Button("Delete", role: .destructive) { deleting = user }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .refreshable { await load() }
        .task(id: server.id) { await load() }
        .overlay {
            if !loading && users.isEmpty && error == nil {
                ContentUnavailableView {
                    Label("No users", systemImage: "person.crop.circle")
                } description: {
                    Text("Create one to get started.")
                } actions: {
                    Button("New User") { showingCreate = true }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await load() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem {
                Button { showingCreate = true } label: {
                    Label("New User", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateUserView(server: server) { _ in
                Task { await load() }
            }
        }
        .alert("Rename user", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        ), presenting: renaming) { user in
            TextField("New name", text: $renameText)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Rename") { Task { await rename(user) } }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { user in
            Text("Rename `\(user.name)` to:")
        }
        .confirmationDialog(
            "Delete user?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            presenting: deleting
        ) { user in
            Button("Delete `\(user.name)`", role: .destructive) {
                Task { await delete(user) }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { user in
            Text("Users with nodes cannot be deleted. Move or delete their nodes first.")
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
            users = try await client.users().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rename(_ user: HSUser) async {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !newName.isEmpty, newName != user.name else { return }
        guard let key = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            _ = try await client.renameUser(id: user.id, newName: newName)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ user: HSUser) async {
        deleting = nil
        guard let key = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            try await client.deleteUser(id: user.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
