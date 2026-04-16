import SwiftUI

@main
struct TailfrontApp: App {
    @StateObject private var servers = ServerStore()
    @StateObject private var nodeMonitor: NodeMonitor

    init() {
        let store = ServerStore()
        _servers = StateObject(wrappedValue: store)
        _nodeMonitor = StateObject(wrappedValue: NodeMonitor(servers: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(servers)
                .environmentObject(nodeMonitor)
                .onAppear { nodeMonitor.start() }
                .onDisappear { nodeMonitor.stop() }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 640)
        .windowToolbarStyle(.unified)
        #endif
    }
}
