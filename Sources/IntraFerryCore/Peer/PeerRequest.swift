import Foundation

public struct PeerRequest: Codable, Equatable, Sendable {
    public var deviceId: UUID
    public var protocolVersion: String
    public var token: AuthToken

    public init(deviceId: UUID, protocolVersion: String, token: AuthToken) {
        self.deviceId = deviceId
        self.protocolVersion = protocolVersion
        self.token = token
    }
}
