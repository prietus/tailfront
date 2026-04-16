import SwiftUI

struct MoveNodeView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let server: Server
    let node: HSNode
    var onMoved: (HSNode) -> Void

    @State private var users: [HSUser] = []
    @State private var selectedUserID: String?
    @State private var loading = true
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Move `\(node.displayName)` to user") {
                    if loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Picker("User", selection: $selectedUserID) {
                            ForEach(users) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.inline)
                        #endif
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Move Node")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { await move() } }
                        .disabled(submitting || selectedUserID == nil || selectedUserID == node.user?.id)
                }
            }
            .task { await loadUsers() }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    private func loadUsers() async {
        guard let key = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            loading = false
            return
        }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            users = try await client.users().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            selectedUserID = node.user?.id ?? users.first?.id
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func move() async {
        guard let targetID = selectedUserID,
              let apiKey = servers.apiKey(for: server) else { return }
        submitting = true
        defer { submitting = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            let updated = try await client.moveNode(id: node.id, toUserID: targetID)
            onMoved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
