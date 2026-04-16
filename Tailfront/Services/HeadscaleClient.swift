import Foundation

struct HeadscaleClient {
    let baseURL: URL
    let apiKey: String
    let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    enum HSError: LocalizedError {
        case badResponse
        case http(Int, String?)

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Invalid response"
            case .http(let code, let body):
                if let body, let msg = Self.extractMessage(from: body) {
                    return msg
                }
                return "HTTP \(code)\(body.map { ": \($0)" } ?? "")"
            }
        }

        private static func extractMessage(from body: String) -> String? {
            guard let data = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = obj["message"] as? String else {
                return nil
            }
            return msg
        }
    }

    func users() async throws -> [HSUser] {
        let r: HSUsersResponse = try await get("api/v1/user")
        return r.users
    }

    func nodes() async throws -> [HSNode] {
        let r: HSNodesResponse = try await get("api/v1/node")
        return r.nodes
    }

    func approveRoutes(nodeID: String, routes: [String]) async throws -> HSNode {
        struct Body: Encodable { let routes: [String] }
        struct Resp: Decodable { let node: HSNode }
        let r: Resp = try await post("api/v1/node/\(nodeID)/approve_routes", body: Body(routes: routes))
        return r.node
    }

    func preAuthKeys(userID: String) async throws -> [HSPreAuthKey] {
        let r: HSPreAuthKeysResponse = try await get(
            "api/v1/preauthkey",
            query: [URLQueryItem(name: "user", value: userID)]
        )
        return r.preAuthKeys
    }

    func createPreAuthKey(
        userID: String,
        reusable: Bool,
        ephemeral: Bool,
        expiration: Date,
        aclTags: [String]
    ) async throws -> HSPreAuthKey {
        struct Body: Encodable {
            let user: String
            let reusable: Bool
            let ephemeral: Bool
            let expiration: String
            let aclTags: [String]
        }
        struct Resp: Decodable { let preAuthKey: HSPreAuthKey }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let body = Body(
            user: userID,
            reusable: reusable,
            ephemeral: ephemeral,
            expiration: iso.string(from: expiration),
            aclTags: aclTags
        )
        let r: Resp = try await post("api/v1/preauthkey", body: body)
        return r.preAuthKey
    }

    func expirePreAuthKey(userID: String, key: String) async throws {
        struct Body: Encodable { let user: String; let key: String }
        let _: Empty = try await post("api/v1/preauthkey/expire", body: Body(user: userID, key: key))
    }

    // MARK: Users

    func createUser(name: String, displayName: String?, email: String?) async throws -> HSUser {
        struct Body: Encodable {
            let name: String
            let displayName: String?
            let email: String?
        }
        struct Resp: Decodable { let user: HSUser }
        let r: Resp = try await post("api/v1/user", body: Body(
            name: name,
            displayName: (displayName?.isEmpty ?? true) ? nil : displayName,
            email: (email?.isEmpty ?? true) ? nil : email
        ))
        return r.user
    }

    func renameUser(id: String, newName: String) async throws -> HSUser {
        struct Resp: Decodable { let user: HSUser }
        let encoded = newName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newName
        let r: Resp = try await postNoBody("api/v1/user/\(id)/rename/\(encoded)")
        return r.user
    }

    func deleteUser(id: String) async throws {
        let _: Empty = try await delete("api/v1/user/\(id)")
    }

    // MARK: Node mutations

    func renameNode(id: String, newName: String) async throws -> HSNode {
        struct Resp: Decodable { let node: HSNode }
        let encoded = newName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newName
        let r: Resp = try await postNoBody("api/v1/node/\(id)/rename/\(encoded)")
        return r.node
    }

    func moveNode(id: String, toUserID: String) async throws -> HSNode {
        struct Body: Encodable { let user: String }
        struct Resp: Decodable { let node: HSNode }
        let r: Resp = try await post("api/v1/node/\(id)/user", body: Body(user: toUserID))
        return r.node
    }

    func expireNode(id: String) async throws -> HSNode {
        struct Resp: Decodable { let node: HSNode }
        let r: Resp = try await postNoBody("api/v1/node/\(id)/expire")
        return r.node
    }

    func setNodeTags(id: String, tags: [String]) async throws -> HSNode {
        struct Body: Encodable { let tags: [String] }
        struct Resp: Decodable { let node: HSNode }
        let r: Resp = try await post("api/v1/node/\(id)/tags", body: Body(tags: tags))
        return r.node
    }

    func deleteNode(id: String) async throws {
        let _: Empty = try await delete("api/v1/node/\(id)")
    }

    // MARK: Node registration

    func registerNode(user: String, key: String) async throws -> HSNode {
        struct Resp: Decodable { let node: HSNode }
        let r: Resp = try await postNoBody(
            "api/v1/node/register",
            query: [
                URLQueryItem(name: "user", value: user),
                URLQueryItem(name: "key", value: key),
            ]
        )
        return r.node
    }

    /// Fetches pending nodekeys from the tailfront helper endpoint on the server.
    func pendingNodes() async throws -> [HSPendingNode] {
        var url = baseURL
        url.append(path: "tailfront/pending")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        return (try? JSONDecoder().decode([HSPendingNode].self, from: data)) ?? []
    }

    /// Denies a pending node, removing it from the pending queue.
    func denyPendingNode(key: String) async throws {
        // Strip "nodekey:" prefix — send only the raw key in the path to avoid encoding issues.
        let rawKey = key.hasPrefix("nodekey:") ? String(key.dropFirst(8)) : key
        var url = baseURL
        url.append(path: "tailfront/pending/\(rawKey)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HSError.badResponse
        }
    }

    // MARK: Policy

    func policy() async throws -> HSPolicy {
        try await get("api/v1/policy")
    }

    func updatePolicy(_ text: String) async throws -> HSPolicy {
        struct Body: Encodable { let policy: String }
        return try await put("api/v1/policy", body: Body(policy: text))
    }

    // MARK: transport

    private struct Empty: Decodable {}

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(makeRequest(path, method: "GET", query: query, body: nil))
    }

    private func post<R: Decodable, B: Encodable>(_ path: String, body: B) async throws -> R {
        let data = try JSONEncoder().encode(body)
        return try await send(makeRequest(path, method: "POST", query: [], body: data))
    }

    private func postNoBody<R: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> R {
        try await send(makeRequest(path, method: "POST", query: query, body: nil))
    }

    private func delete<R: Decodable>(_ path: String) async throws -> R {
        try await send(makeRequest(path, method: "DELETE", query: [], body: nil))
    }

    private func put<R: Decodable, B: Encodable>(_ path: String, body: B) async throws -> R {
        let data = try JSONEncoder().encode(body)
        return try await send(makeRequest(path, method: "PUT", query: [], body: data))
    }

    private func makeRequest(_ path: String, method: String, query: [URLQueryItem], body: Data?) -> URLRequest {
        var url = baseURL
        url.append(path: path)
        if !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query
            if let q = comps.url { url = q }
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw HSError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HSError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let plain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = withFraction.date(from: s) { return d }
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unparseable date: \(s)")
        }
        return d
    }()
}
