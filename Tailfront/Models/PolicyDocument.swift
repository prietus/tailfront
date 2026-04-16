import Foundation

struct PolicyDocument {
    var groups: [Group] = []
    var tagOwners: [TagOwners] = []
    var hosts: [Host] = []
    var acls: [ACLRule] = []
    var ssh: [SSHRule] = []
    var autoApprovers: AutoApprovers?

    struct Group: Identifiable, Hashable {
        let name: String
        let members: [String]
        var id: String { name }
    }

    struct TagOwners: Identifiable, Hashable {
        let tag: String
        let owners: [String]
        var id: String { tag }
    }

    struct Host: Identifiable, Hashable {
        let name: String
        let value: String
        var id: String { name }
    }

    struct ACLRule: Identifiable, Hashable {
        let id = UUID()
        let action: String
        let proto: String?
        let src: [String]
        let dst: [String]
    }

    struct SSHRule: Identifiable, Hashable {
        let id = UUID()
        let action: String
        let src: [String]
        let dst: [String]
        let users: [String]
    }

    struct AutoApprovers: Hashable {
        var routes: [Route] = []
        var exitNode: [String] = []

        struct Route: Identifiable, Hashable {
            let cidr: String
            let approvers: [String]
            var id: String { cidr }
        }
    }

    var isEmpty: Bool {
        groups.isEmpty && tagOwners.isEmpty && hosts.isEmpty &&
        acls.isEmpty && ssh.isEmpty && autoApprovers == nil
    }
}

enum PolicyParser {
    /// Parses HuJSON (JSON with // and /* */ comments plus trailing commas) into a typed document.
    /// Returns nil when the text is not parseable — caller should fall back to text-only view.
    static func parse(_ text: String) -> PolicyDocument? {
        let cleaned = stripHuJSON(text)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
        else { return nil }
        return build(from: obj)
    }

    /// Strips // line comments, /* */ block comments, and trailing commas.
    /// Preserves comment-like characters that appear inside string literals.
    static func stripHuJSON(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)

        var inString = false
        var stringEscape = false
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if stringEscape {
                    stringEscape = false
                } else if c == "\\" {
                    stringEscape = true
                } else if c == "\"" {
                    inString = false
                }
                i = input.index(after: i)
                continue
            }

            if c == "\"" {
                inString = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            // Line comment //...
            if c == "/", input.index(after: i) < input.endIndex, input[input.index(after: i)] == "/" {
                while i < input.endIndex, input[i] != "\n" { i = input.index(after: i) }
                continue
            }

            // Block comment /* ... */
            if c == "/", input.index(after: i) < input.endIndex, input[input.index(after: i)] == "*" {
                i = input.index(i, offsetBy: 2)
                while i < input.endIndex {
                    if input[i] == "*",
                       input.index(after: i) < input.endIndex,
                       input[input.index(after: i)] == "/"
                    {
                        i = input.index(i, offsetBy: 2)
                        break
                    }
                    i = input.index(after: i)
                }
                continue
            }

            out.append(c)
            i = input.index(after: i)
        }

        // Remove trailing commas before } or ]
        return removeTrailingCommas(out)
    }

    private static func removeTrailingCommas(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        let chars = Array(s)
        var idx = 0
        var inString = false
        var stringEscape = false
        while idx < chars.count {
            let c = chars[idx]
            if inString {
                out.append(c)
                if stringEscape { stringEscape = false }
                else if c == "\\" { stringEscape = true }
                else if c == "\"" { inString = false }
                idx += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); idx += 1; continue }
            if c == "," {
                var j = idx + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    idx += 1
                    continue
                }
            }
            out.append(c)
            idx += 1
        }
        return out
    }

    private static func build(from obj: [String: Any]) -> PolicyDocument {
        var doc = PolicyDocument()

        if let groups = obj["groups"] as? [String: Any] {
            doc.groups = groups.keys.sorted().map { name in
                PolicyDocument.Group(name: name, members: stringList(groups[name]))
            }
        }

        if let owners = obj["tagOwners"] as? [String: Any] {
            doc.tagOwners = owners.keys.sorted().map { tag in
                PolicyDocument.TagOwners(tag: tag, owners: stringList(owners[tag]))
            }
        }

        if let hosts = obj["hosts"] as? [String: Any] {
            doc.hosts = hosts.keys.sorted().map { name in
                PolicyDocument.Host(name: name, value: (hosts[name] as? String) ?? "")
            }
        }

        if let acls = obj["acls"] as? [[String: Any]] {
            doc.acls = acls.map { a in
                PolicyDocument.ACLRule(
                    action: (a["action"] as? String) ?? "",
                    proto: a["proto"] as? String,
                    src: stringList(a["src"]),
                    dst: stringList(a["dst"])
                )
            }
        }

        if let ssh = obj["ssh"] as? [[String: Any]] {
            doc.ssh = ssh.map { s in
                PolicyDocument.SSHRule(
                    action: (s["action"] as? String) ?? "",
                    src: stringList(s["src"]),
                    dst: stringList(s["dst"]),
                    users: stringList(s["users"])
                )
            }
        }

        if let ap = obj["autoApprovers"] as? [String: Any] {
            var approvers = PolicyDocument.AutoApprovers()
            if let routes = ap["routes"] as? [String: Any] {
                approvers.routes = routes.keys.sorted().map { cidr in
                    .init(cidr: cidr, approvers: stringList(routes[cidr]))
                }
            }
            approvers.exitNode = stringList(ap["exitNode"])
            if !approvers.routes.isEmpty || !approvers.exitNode.isEmpty {
                doc.autoApprovers = approvers
            }
        }

        return doc
    }

    private static func stringList(_ v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let s = v as? String { return [s] }
        return []
    }

    // MARK: Surgical edits

    /// Returns `text` with the ACL at `aclIndex` removed, preserving HuJSON comments and
    /// formatting in the rest of the document. Returns nil if the index is out of range or
    /// the scan fails.
    static func removingACL(at aclIndex: Int, from text: String) -> String? {
        let ranges = findACLRanges(in: text)
        guard ranges.indices.contains(aclIndex) else { return nil }
        let remove: Range<String.Index>
        if ranges.count == 1 {
            remove = ranges[0]
        } else if aclIndex == 0 {
            // Consume object 0 and the gap (comma + whitespace) up to the next element.
            remove = ranges[0].lowerBound..<ranges[1].lowerBound
        } else {
            // Consume the gap after the previous element (leading comma) and this object.
            remove = ranges[aclIndex - 1].upperBound..<ranges[aclIndex].upperBound
        }
        var new = text
        new.removeSubrange(remove)
        return new
    }

    static func findACLRanges(in text: String) -> [Range<String.Index>] {
        var scanner = HuJSONScanner(text: text)
        return scanner.findACLRanges()
    }
}

private struct HuJSONScanner {
    let text: String
    var index: String.Index

    init(text: String) {
        self.text = text
        self.index = text.startIndex
    }

    var isAtEnd: Bool { index == text.endIndex }

    mutating func advance() {
        if !isAtEnd { index = text.index(after: index) }
    }

    mutating func skipTrivia() {
        while !isAtEnd {
            let c = text[index]
            if c.isWhitespace { advance(); continue }
            if c == "/" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    if text[next] == "/" {
                        while !isAtEnd, text[index] != "\n" { advance() }
                        continue
                    }
                    if text[next] == "*" {
                        advance(); advance()
                        while !isAtEnd {
                            if text[index] == "*" {
                                let n = text.index(after: index)
                                if n < text.endIndex, text[n] == "/" {
                                    advance(); advance()
                                    break
                                }
                            }
                            advance()
                        }
                        continue
                    }
                }
            }
            break
        }
    }

    mutating func skipString() {
        guard !isAtEnd, text[index] == "\"" else { return }
        advance()
        while !isAtEnd {
            let c = text[index]
            if c == "\\" {
                advance()
                if !isAtEnd { advance() }
                continue
            }
            if c == "\"" { advance(); return }
            advance()
        }
    }

    mutating func skipBalanced(open: Character, close: Character) {
        guard !isAtEnd, text[index] == open else { return }
        advance()
        var depth = 1
        while !isAtEnd, depth > 0 {
            skipTrivia()
            if isAtEnd { return }
            let c = text[index]
            if c == "\"" { skipString(); continue }
            if c == open { depth += 1; advance(); continue }
            if c == close { depth -= 1; advance(); continue }
            if c == "{" { skipBalanced(open: "{", close: "}"); continue }
            if c == "[" { skipBalanced(open: "[", close: "]"); continue }
            advance()
        }
    }

    mutating func parseKey() -> String? {
        skipTrivia()
        guard !isAtEnd, text[index] == "\"" else { return nil }
        advance()
        var s = ""
        while !isAtEnd {
            let c = text[index]
            if c == "\\" {
                advance()
                if !isAtEnd {
                    let e = text[index]
                    switch e {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "\"": s.append("\"")
                    case "\\": s.append("\\")
                    case "/": s.append("/")
                    default: s.append(e)
                    }
                    advance()
                }
                continue
            }
            if c == "\"" { advance(); return s }
            s.append(c)
            advance()
        }
        return nil
    }

    mutating func skipValue() {
        skipTrivia()
        guard !isAtEnd else { return }
        let c = text[index]
        if c == "\"" { skipString(); return }
        if c == "{" { skipBalanced(open: "{", close: "}"); return }
        if c == "[" { skipBalanced(open: "[", close: "]"); return }
        while !isAtEnd {
            let ch = text[index]
            if ch == "," || ch == "}" || ch == "]" || ch.isWhitespace { break }
            advance()
        }
    }

    mutating func findACLRanges() -> [Range<String.Index>] {
        skipTrivia()
        guard !isAtEnd, text[index] == "{" else { return [] }
        advance()
        while !isAtEnd {
            skipTrivia()
            if isAtEnd { break }
            if text[index] == "}" { return [] }
            guard let key = parseKey() else { return [] }
            skipTrivia()
            if !isAtEnd, text[index] == ":" { advance() }
            skipTrivia()
            if key == "acls" {
                return parseACLArray()
            }
            skipValue()
            skipTrivia()
            if !isAtEnd, text[index] == "," { advance() }
        }
        return []
    }

    mutating func parseACLArray() -> [Range<String.Index>] {
        skipTrivia()
        guard !isAtEnd, text[index] == "[" else { return [] }
        advance()
        var ranges: [Range<String.Index>] = []
        while !isAtEnd {
            skipTrivia()
            if isAtEnd { break }
            if text[index] == "]" { advance(); break }
            if text[index] == "{" {
                let start = index
                skipBalanced(open: "{", close: "}")
                ranges.append(start..<index)
            } else {
                skipValue()
            }
            skipTrivia()
            if !isAtEnd, text[index] == "," { advance() }
        }
        return ranges
    }
}
