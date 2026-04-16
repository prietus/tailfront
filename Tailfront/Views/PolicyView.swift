import SwiftUI

struct PolicyView: View {
    @EnvironmentObject var servers: ServerStore
    let server: Server

    @State private var text: String = ""
    @State private var originalText: String = ""
    @State private var updatedAt: Date?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var info: String?
    @State private var mode: Mode = .structure

    private enum Mode: String, CaseIterable, Identifiable {
        case structure = "Structure"
        case text = "Text"
        var id: String { rawValue }
    }

    private var dirty: Bool { text != originalText }
    private var document: PolicyDocument? { PolicyParser.parse(text) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if loading && text.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding()
            }

            Group {
                switch mode {
                case .structure:
                    if let doc = document {
                        StructureBrowser(document: doc, onDeleteACL: deleteACL)
                    } else if !text.isEmpty {
                        ContentUnavailableView {
                            Label("Unparseable policy", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("Switch to Text to edit.")
                        }
                    }
                case .text:
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .overlay(alignment: .bottomTrailing) {
                            if dirty {
                                Text("Modified")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.orange.opacity(0.2), in: Capsule())
                                    .padding(8)
                            }
                        }
                }
            }

            HStack(spacing: 12) {
                if let updatedAt {
                    Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("File-backed policy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let info {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .task(id: server.id) { await load() }
        .toolbar {
            ToolbarItem {
                Button {
                    Clipboard.copy(text)
                    info = "Copied"
                    dismissInfoAfter(1.5)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            ToolbarItem {
                Button {
                    text = originalText
                    error = nil
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(!dirty)
            }
            ToolbarItem {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem {
                Button {
                    Task { await save() }
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .disabled(!dirty || saving)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func load() async {
        guard originalText.isEmpty else { return }
        await reload()
    }

    private func reload() async {
        guard let key = servers.apiKey(for: server) else {
            error = "No API key stored for this server"
            return
        }
        loading = true
        defer { loading = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            let policy = try await client.policy()
            text = policy.policy
            originalText = policy.policy
            updatedAt = policy.updatedAt
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let key = servers.apiKey(for: server), dirty else { return }
        saving = true
        defer { saving = false }
        do {
            let client = HeadscaleClient(baseURL: server.baseURL, apiKey: key)
            let policy = try await client.updatePolicy(text)
            originalText = policy.policy
            text = policy.policy
            updatedAt = policy.updatedAt
            error = nil
            info = "Saved"
            dismissInfoAfter(1.5)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteACL(at index: Int) {
        if let updated = PolicyParser.removingACL(at: index, from: text) {
            text = updated
        }
    }

    private func dismissInfoAfter(_ seconds: Double) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            info = nil
        }
    }
}

private struct StructureBrowser: View {
    let document: PolicyDocument
    var onDeleteACL: ((Int) -> Void)? = nil

    var body: some View {
        if document.isEmpty {
            ContentUnavailableView {
                Label("Empty policy", systemImage: "doc.text")
            } description: {
                Text("Switch to Text to add rules.")
            }
        } else {
            List {
                if !document.groups.isEmpty {
                    Section("Groups (\(document.groups.count))") {
                        ForEach(document.groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.system(.body, design: .monospaced))
                                ChipRow(items: group.members, color: .blue)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !document.tagOwners.isEmpty {
                    Section("Tag Owners (\(document.tagOwners.count))") {
                        ForEach(document.tagOwners) { owner in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(owner.tag)
                                    .font(.system(.body, design: .monospaced))
                                ChipRow(items: owner.owners, color: .purple)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !document.hosts.isEmpty {
                    Section("Hosts (\(document.hosts.count))") {
                        ForEach(document.hosts) { host in
                            HStack {
                                Text(host.name)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(host.value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !document.acls.isEmpty {
                    Section("ACLs (\(document.acls.count))") {
                        ForEach(Array(document.acls.enumerated()), id: \.offset) { idx, rule in
                            ACLRuleRow(rule: rule)
                                .contextMenu {
                                    if let onDeleteACL {
                                        Button(role: .destructive) {
                                            onDeleteACL(idx)
                                        } label: {
                                            Label("Delete Rule", systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    if let onDeleteACL {
                                        Button(role: .destructive) {
                                            onDeleteACL(idx)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                }

                if !document.ssh.isEmpty {
                    Section("SSH (\(document.ssh.count))") {
                        ForEach(document.ssh) { rule in
                            SSHRuleRow(rule: rule)
                        }
                    }
                }

                if let ap = document.autoApprovers {
                    Section("Auto Approvers") {
                        if !ap.routes.isEmpty {
                            ForEach(ap.routes) { route in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.cidr)
                                        .font(.system(.body, design: .monospaced))
                                    ChipRow(items: route.approvers, color: .teal)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        if !ap.exitNode.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exit Node")
                                    .font(.subheadline)
                                ChipRow(items: ap.exitNode, color: .orange)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }
}

private struct ACLRuleRow: View {
    let rule: PolicyDocument.ACLRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ActionBadge(action: rule.action)
                if let proto = rule.proto, !proto.isEmpty {
                    Text(proto)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    Text("from")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    ChipRow(items: rule.src, color: .blue)
                }
                HStack(alignment: .top, spacing: 6) {
                    Text("to")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    ChipRow(items: rule.dst, color: .green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SSHRuleRow: View {
    let rule: PolicyDocument.SSHRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActionBadge(action: rule.action)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    Text("from").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    ChipRow(items: rule.src, color: .blue)
                }
                HStack(alignment: .top, spacing: 6) {
                    Text("to").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    ChipRow(items: rule.dst, color: .green)
                }
                if !rule.users.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text("users").font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        ChipRow(items: rule.users, color: .purple)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ActionBadge: View {
    let action: String
    var body: some View {
        let color: Color = action == "accept" ? .green : (action == "drop" ? .red : .secondary)
        Text(action.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct ChipRow: View {
    let items: [String]
    let color: Color

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
