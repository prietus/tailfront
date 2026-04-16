import SwiftUI

struct ServerEditView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let existing: Server?

    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var apiKey: String = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("Base URL", text: $urlString)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }
                Section("API Key") {
                    SecureField(existing == nil ? "API key" : "Leave empty to keep current", text: $apiKey)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Add Server" : "Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    urlString = existing.baseURL.absoluteString
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func save() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, scheme.hasPrefix("http"), url.host() != nil else {
            error = "Invalid URL"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { error = "Name required"; return }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            var updated = existing
            updated.name = trimmedName
            updated.baseURL = url
            servers.update(updated, apiKey: trimmedKey.isEmpty ? nil : trimmedKey)
        } else {
            guard !trimmedKey.isEmpty else { error = "API key required"; return }
            servers.add(Server(name: trimmedName, baseURL: url), apiKey: trimmedKey)
        }
        dismiss()
    }
}
