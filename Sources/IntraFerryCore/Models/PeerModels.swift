import Foundation

public struct PeerConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var host: String
    public var port: Int
    public var tokenKey: String
    public var localDeviceName: String

    public init(id: UUID, displayName: String, host: String, port: Int, tokenKey: String, localDeviceName: String) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.tokenKey = tokenKey
        self.localDeviceName = localDeviceName
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

public struct LocalDeviceConfig: Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var servicePort: Int

    public init(id: UUID, displayName: String, servicePort: Int) {
        self.id = id
        self.displayName = displayName
        self.servicePort = servicePort
    }
}
