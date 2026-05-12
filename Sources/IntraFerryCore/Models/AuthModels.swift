import Foundation

public struct AuthToken: Codable, Equatable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var redacted: String {
        guard rawValue.count > 6 else { return "******" }
        return "\(rawValue.prefix(3))...\(rawValue.suffix(3))"
    }
}

public struct AuthenticatedPeerRequest: Equatable, Sendable {
    public var deviceId: UUID
    public var protocolVersion: String
    public var token: AuthToken

    public init(deviceId: UUID, protocolVersion: String, token: AuthToken) {
        self.deviceId = deviceId
        self.protocolVersion = protocolVersion
        self.token = token
    }
}
