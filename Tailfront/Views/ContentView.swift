import SwiftUI

struct ContentView: View {
    @EnvironmentObject var servers: ServerStore
    @State private var showingAdd = false
    @State private var editing: Server?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selected = servers.selected {
                ServerDetailView(server: selected)
            } else {
                ContentUnavailableView {
                    Label("No server selected", systemImage: "server.rack")
                } description: {
                    Text("Add a Headscale server from the sidebar.")
                } actions: {
                    Button("Add Server") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $servers.selectedID) {
            Section("Servers") {
                ForEach(servers.servers) { server in
                    ServerSidebarRow(
                        server: server,
                        onEdit: { editing = server },
                        onRemove: { servers.remove(server) }
                    )
                }
            }
        }
        .navigationTitle("Tailfront")
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        .sheet(isPresented: $showingAdd) {
            ServerEditView(existing: nil)
        }
        .sheet(item: $editing) { s in
            ServerEditView(existing: s)
        }
    }
}

private struct ServerSidebarRow: View {
    let server: Server
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        NavigationLink(value: server.id) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.headline)
                    Text(server.baseURL.host() ?? server.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "server.rack")
                    .foregroundStyle(.tint)
            }
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}
