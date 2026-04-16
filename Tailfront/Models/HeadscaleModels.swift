import Foundation

struct HSUser: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayName: String?
    let email: String?
    let createdAt: Date?
}

struct HSUsersResponse: Codable {
    let users: [HSUser]
}

struct HSNode: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let givenName: String?
    let ipAddresses: [String]?
    let online: Bool?
    let lastSeen: Date?
    let expiry: Date?
    let createdAt: Date?
    let user: HSUser?
    let validTags: [String]?
    let forcedTags: [String]?
    let approvedRoutes: [String]?
    let availableRoutes: [String]?
    let subnetRoutes: [String]?

    var displayName: String { givenName ?? name }
    var primaryIP: String? { ipAddresses?.first(where: { !$0.contains(":") }) ?? ipAddresses?.first }
    var isOnline: Bool { online ?? false }
    var tags: [String] { validTags ?? forcedTags ?? [] }
}

struct HSNodesResponse: Codable {
    let nodes: [HSNode]
}

struct HSPreAuthKey: Identifiable, Codable, Hashable {
    let id: String
    let key: String
    let reusable: Bool
    let ephemeral: Bool
    let used: Bool
    let expiration: Date?
    let createdAt: Date?
    let aclTags: [String]?
    let user: HSUser?

    var isExpired: Bool {
        guard let expiration else { return false }
        return expiration < Date()
    }

    var isActive: Bool { !used && !isExpired }
}

struct HSPreAuthKeysResponse: Codable {
    let preAuthKeys: [HSPreAuthKey]
}

struct HSPolicy: Codable, Hashable {
    let policy: String
    let updatedAt: Date?
}

struct HSPendingNode: Codable, Identifiable, Hashable {
    let key: String
    let ip: String?
    let device: String?
    var id: String { key }
}
