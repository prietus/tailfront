import Foundation
import SwiftUI

@MainActor
final class ServerStore: ObservableObject {
    @Published var servers: [Server] = []
    @Published var selectedID: Server.ID?

    private let serversKey = "tailfront.servers.v1"
    private let selectedKey = "tailfront.selected.v1"
    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var externalObserver: NSObjectProtocol?

    init() {
        load()
        externalObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadServersFromCloud() }
        }
        kv.synchronize()
    }

    deinit {
        if let externalObserver {
            NotificationCenter.default.removeObserver(externalObserver)
        }
    }

    var selected: Server? {
        servers.first(where: { $0.id == selectedID })
    }

    func add(_ server: Server, apiKey: String) {
        try? KeychainStore.set(apiKey, for: server.id.uuidString)
        servers.append(server)
        selectedID = server.id
        save()
    }

    func update(_ server: Server, apiKey: String?) {
        if let apiKey, !apiKey.isEmpty {
            try? KeychainStore.set(apiKey, for: server.id.uuidString)
        }
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        }
        save()
    }

    func remove(_ server: Server) {
        KeychainStore.remove(server.id.uuidString)
        servers.removeAll { $0.id == server.id }
        if selectedID == server.id { selectedID = servers.first?.id }
        save()
    }

    func apiKey(for server: Server) -> String? {
        KeychainStore.get(server.id.uuidString)
    }

    private func load() {
        // Servers list: cloud first, then local fallback.
        if let data = kv.data(forKey: serversKey) ?? defaults.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([Server].self, from: data) {
            servers = decoded
        }
        // Selected server: per-device UI state, never synced.
        if let sel = defaults.string(forKey: selectedKey) {
            selectedID = UUID(uuidString: sel)
        }
        if selectedID == nil || !servers.contains(where: { $0.id == selectedID }) {
            selectedID = servers.first?.id
        }
    }

    private func loadServersFromCloud() {
        guard let data = kv.data(forKey: serversKey),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else {
            return
        }
        servers = decoded
        if selectedID == nil || !servers.contains(where: { $0.id == selectedID }) {
            selectedID = servers.first?.id
        }
        defaults.set(data, forKey: serversKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            kv.set(data, forKey: serversKey)
            defaults.set(data, forKey: serversKey)
        }
        defaults.set(selectedID?.uuidString, forKey: selectedKey)
        kv.synchronize()
    }
}
