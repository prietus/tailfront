import SwiftUI

struct EditNodeTagsView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let server: Server
    let node: HSNode
    var onUpdated: (HSNode) -> Void

    @State private var tagsText: String = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("tag:foo, tag:bar", text: $tagsText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Forced tags")
                } footer: {
                    Text("Comma-separated. Each must start with `tag:`. Empty clears all forced tags.")
                        .font(.caption)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Node tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(submitting)
                }
            }
            .onAppear {
                tagsText = (node.forcedTags ?? []).joined(separator: ", ")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }

    private func save() async {
        guard let apiKey = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for t in tags where !t.hasPrefix("tag:") {
            error = "Tag `\(t)` must start with `tag:`"
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            let updated = try await client.setNodeTags(id: node.id, tags: tags)
            onUpdated(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
