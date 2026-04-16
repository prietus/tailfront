import SwiftUI

struct CreateUserView: View {
    @EnvironmentObject var servers: ServerStore
    @Environment(\.dismiss) private var dismiss

    let server: Server
    var onCreated: (HSUser) -> Void

    @State private var name = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Display name (optional)", text: $displayName)
                    TextField("Email (optional)", text: $email)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section {} footer: {
                    Text("Name must be unique. For ACL policies, prefer a user identifier that works with `user@` format (e.g. `alice` → `alice@`).")
                        .font(.caption)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New User")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(submitting || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private func create() async {
        guard let apiKey = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: apiKey)
            let user = try await client.createUser(
                name: name.trimmingCharacters(in: .whitespaces),
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces)
            )
            onCreated(user)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
