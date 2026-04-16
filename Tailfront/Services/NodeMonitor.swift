import Foundation
import UserNotifications

/// Periodically polls all configured servers for pending node registrations
/// and fires a local notification when a new one appears.
@MainActor
final class NodeMonitor: ObservableObject {
    private let servers: ServerStore
    private let interval: TimeInterval
    private var timer: Timer?

    @Published var pendingByServer: [UUID: [HSPendingNode]] = [:]

    /// Keys we already notified about (so we don't spam).
    private var notifiedKeys: Set<String> = []

    init(servers: ServerStore, interval: TimeInterval = 30) {
        self.servers = servers
        self.interval = interval
    }

    func start() {
        requestNotificationPermission()
        Task { await pollAll(notify: false) }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollAll(notify: true)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollAll(notify: Bool = true) async {
        for server in servers.servers {
            guard let key = servers.apiKey(for: server) else { continue }
            do {
                let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
                let pending = try await client.pendingNodes()
                pendingByServer[server.id] = pending

                if notify {
                    for node in pending where !notifiedKeys.contains(node.key) {
                        notifiedKeys.insert(node.key)
                        sendNotification(key: node.key, server: server)
                    }
                } else {
                    for node in pending {
                        notifiedKeys.insert(node.key)
                    }
                }
            } catch {
                // Silent on network errors.
            }
        }
    }

    func pendingCount(for serverID: UUID) -> Int {
        pendingByServer[serverID]?.count ?? 0
    }

    private func sendNotification(key: String, server: Server) {
        let content = UNMutableNotificationContent()
        content.title = "Node waiting to join"
        content.body = "A new device wants to register on \(server.name)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pending-\(server.id)-\(key)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
