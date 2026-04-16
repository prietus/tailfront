import SwiftUI

struct CreatePreAuthKeyView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let server: Server
    let userID: String
    var onCreated: (HSPreAuthKey) -> Void

    enum Preset: String, CaseIterable, Identifiable {
        case oneHour = "1 hour"
        case sixHours = "6 hours"
        case oneDay = "1 day"
        case sevenDays = "7 days"
        case thirtyDays = "30 days"
        case custom = "Custom"
        var id: String { rawValue }

        func date(from: Date) -> Date {
            switch self {
            case .oneHour:    return from.addingTimeInterval(3600)
            case .sixHours:   return from.addingTimeInterval(6 * 3600)
            case .oneDay:     return from.addingTimeInterval(86400)
            case .sevenDays:  return from.addingTimeInterval(7 * 86400)
            case .thirtyDays: return from.addingTimeInterval(30 * 86400)
            case .custom:     return from.addingTimeInterval(3600)
            }
        }
    }

    @State private var reusable = false
    @State private var ephemeral = false
    @State private var preset: Preset = .oneDay
    @State private var customDate: Date = Date().addingTimeInterval(86400)
    @State private var tagsText: String = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Options") {
                    Toggle("Reusable", isOn: $reusable)
                    Toggle("Ephemeral", isOn: $ephemeral)
                }

                Section("Expiration") {
                    Picker("Preset", selection: $preset) {
                        ForEach(Preset.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    if preset == .custom {
                        DatePicker("Expires", selection: $customDate, in: Date()...)
                    }
                }

                Section {
                    TextField("tag:foo, tag:bar", text: $tagsText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("ACL Tags")
                } footer: {
                    Text("Comma-separated, each must start with `tag:`")
                        .font(.caption)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Pre-Auth Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(submitting)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private func create() async {
        guard let apiKey = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        let expiration = preset == .custom ? customDate : preset.date(from: Date())
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for tag in tags where !tag.hasPrefix("tag:") {
            error = "Tag `\(tag)` must start with `tag:`"
            return
        }

        submitting = true
        defer { submitting = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            let created = try await client.createPreAuthKey(
                userID: userID,
                reusable: reusable,
                ephemeral: ephemeral,
                expiration: expiration,
                aclTags: tags
            )
            onCreated(created)
            Clipboard.copy(created.key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
