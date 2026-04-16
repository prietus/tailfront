import SwiftUI

struct ServerDetailView: View {
    let server: Server

    enum Tab: String, CaseIterable, Identifiable {
        case nodes = "Nodes"
        case keys = "Keys"
        case users = "Users"
        case policy = "Policy"
        var id: String { rawValue }

        var shortcut: KeyEquivalent {
            switch self {
            case .nodes: return "1"
            case .keys: return "2"
            case .users: return "3"
            case .policy: return "4"
            }
        }
    }

    @State private var tab: Tab = .nodes

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case .nodes: NodesView(server: server)
                    case .keys: PreAuthKeysView(server: server)
                    case .users: UsersView(server: server)
                    case .policy: PolicyView(server: server)
                    }
                }
            }
            .background(tabShortcuts)
            .navigationTitle(server.name)
        }
    }

    private var tabShortcuts: some View {
        ZStack {
            ForEach(Tab.allCases) { t in
                Button("") { tab = t }
                    .keyboardShortcut(t.shortcut, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
