import SwiftUI

struct NodeDetailView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let server: Server
    var onChanged: () -> Void = {}

    @State var node: HSNode
    @State private var pendingRoute: String?
    @State private var error: String?

    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingMove = false
    @State private var showingTags = false
    @State private var showingExpireConfirm = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            Section("Info") {
                LabeledContent("Name", value: node.displayName)
                LabeledContent("ID", value: node.id)
                if let user = node.user?.name {
                    LabeledContent("User", value: user)
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(node.isOnline ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(node.isOnline ? "online" : "offline")
                            .foregroundStyle(node.isOnline ? .green : .secondary)
                    }
                }
                if let seen = node.lastSeen {
                    LabeledContent("Last seen", value: seen.formatted(.relative(presentation: .named)))
                }
                if let created = node.createdAt {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let expiry = node.expiry {
                    LabeledContent("Expires", value: expiry.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let ips = node.ipAddresses, !ips.isEmpty {
                Section("IP addresses") {
                    ForEach(ips, id: \.self) { ip in
                        Text(ip).font(.system(.body, design: .monospaced))
                    }
                }
            }

            if !node.tags.isEmpty {
                Section("Tags") {
                    ForEach(node.tags, id: \.self) { tag in
                        Text(tag)
                    }
                }
            }

            Section {
                let advertised = node.availableRoutes ?? []
                let approved = Set(node.approvedRoutes ?? [])
                if advertised.isEmpty {
                    Text("No routes advertised")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(advertised, id: \.self) { route in
                        RouteToggleRow(
                            route: route,
                            isApproved: approved.contains(route),
                            busy: pendingRoute == route,
                            onToggle: { newValue in
                                Task { await toggle(route: route, approve: newValue) }
                            }
                        )
                    }
                }
            } header: {
                Text("Routes")
            } footer: {
                Text("Toggle a route to approve or revoke it. `0.0.0.0/0` and `::/0` make the node an exit node.")
                    .font(.caption)
            }

            Section("Actions") {
                Button("Rename…") {
                    renameText = node.displayName
                    showingRename = true
                }
                Button("Move to user…") { showingMove = true }
                Button("Edit tags…") { showingTags = true }
                Button("Expire (force re-auth)") { showingExpireConfirm = true }
                Button("Delete node", role: .destructive) { showingDeleteConfirm = true }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(node.displayName)
        .alert("Rename node", isPresented: $showingRename) {
            TextField("New name", text: $renameText)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Rename") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Node names must be globally unique.")
        }
        .sheet(isPresented: $showingMove) {
            MoveNodeView(server: server, node: node) { updated in
                node = updated
                onChanged()
            }
        }
        .sheet(isPresented: $showingTags) {
            EditNodeTagsView(server: server, node: node) { updated in
                node = updated
                onChanged()
            }
        }
        .confirmationDialog(
            "Expire this node?",
            isPresented: $showingExpireConfirm
        ) {
            Button("Expire", role: .destructive) { Task { await expire() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The node will be forced to re-authenticate on next connect.")
        }
        .confirmationDialog(
            "Delete this node?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete `\(node.displayName)`", role: .destructive) { Task { await deleteNode() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the node from Headscale. The device will need to re-register.")
        }
    }

    private func toggle(route: String, approve: Bool) async {
        guard let key = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        var routes = Set(node.approvedRoutes ?? [])
        if approve { routes.insert(route) } else { routes.remove(route) }
        let next = Array(routes).sorted()

        pendingRoute = route
        defer { pendingRoute = nil }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            let updated = try await client.approveRoutes(nodeID: node.id, routes: next)
            node = updated
            onChanged()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rename() async {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != node.displayName else { return }
        guard let key = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            node = try await client.renameNode(id: node.id, newName: newName)
            onChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func expire() async {
        guard let key = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            node = try await client.expireNode(id: node.id)
            onChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteNode() async {
        guard let key = servers.apiKey(for: server) else { return }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            try await client.deleteNode(id: node.id)
            onChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct RouteToggleRow: View {
    let route: String
    let isApproved: Bool
    let busy: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Text(route).font(.system(.body, design: .monospaced))
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { isApproved },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }
        }
    }
}
