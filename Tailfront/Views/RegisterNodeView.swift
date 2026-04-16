import SwiftUI

struct RegisterNodeView: View {
    @EnvironmentObject var servers: ServerStore
    let server: Server
    var prefillKey: String = ""
    var onRegistered: (HSNode) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var nodeKey = ""
    @State private var users: [HSUser] = []
    @State private var selectedUserID: String?
    @State private var loading = false
    @State private var registering = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if prefillKey.isEmpty {
                    Section("Node Key") {
                        TextField("Paste node key", text: $nodeKey)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                } else {
                    Section("Node Key") {
                        Text(nodeKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Assign to User") {
                    if loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Picker("User", selection: $selectedUserID) {
                            ForEach(users) { user in
                                Text(user.name).tag(Optional(user.id))
                            }
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Register Node")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Register") {
                        Task { await register() }
                    }
                    .disabled(cleanedKey.isEmpty || selectedUserID == nil || registering)
                }
            }
            .task {
                if !prefillKey.isEmpty { nodeKey = prefillKey }
                await loadUsers()
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 260)
        #endif
    }

    private var cleanedKey: String {
        var k = nodeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasPrefix("nodekey:") { k = String(k.dropFirst(8)) }
        return k
    }

    private func loadUsers() async {
        guard let key = servers.apiKey(for: server) else { return }
        loading = true
        defer { loading = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            users = try await client.users()
            if selectedUserID == nil {
                selectedUserID = users.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func register() async {
        guard let key = servers.apiKey(for: server),
              let userID = selectedUserID,
              let userName = users.first(where: { $0.id == userID })?.name else { return }
        registering = true
        defer { registering = false }
        error = nil
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            let node = try await client.registerNode(user: userName, key: cleanedKey)
            // Remove from pending queue
            try? await client.denyPendingNode(key: nodeKey)
            onRegistered(node)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
