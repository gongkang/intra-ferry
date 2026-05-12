import Foundation

public struct PeerConfig: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let host: String
    public let port: Int
    public let tokenKey: String
    public let localDeviceName: String
    private let validatedBaseURL: URL

    public enum ValidationError: LocalizedError, Equatable, Sendable {
        case emptyHost
        case whitespaceInHost(String)
        case invalidPort(Int)
        case invalidURL(host: String, port: Int)

        public var errorDescription: String? {
            switch self {
            case .emptyHost:
                return "Peer host cannot be empty."
            case let .whitespaceInHost(host):
                return "Peer host \(host) cannot contain whitespace."
            case let .invalidPort(port):
                return "Peer port \(port) must be between 1 and 65535."
            case let .invalidURL(host, port):
                return "Peer host \(host) and port \(port) do not form a valid HTTP URL."
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case host
        case port
        case tokenKey
        case localDeviceName
    }

    public init(id: UUID, displayName: String, host: String, port: Int, tokenKey: String, localDeviceName: String) throws {
        let baseURL = try Self.makeBaseURL(host: host, port: port)

        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.tokenKey = tokenKey
        self.localDeviceName = localDeviceName
        self.validatedBaseURL = baseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            try self.init(
                id: container.decode(UUID.self, forKey: .id),
                displayName: container.decode(String.self, forKey: .displayName),
                host: container.decode(String.self, forKey: .host),
                port: container.decode(Int.self, forKey: .port),
                tokenKey: container.decode(String.self, forKey: .tokenKey),
                localDeviceName: container.decode(String.self, forKey: .localDeviceName)
            )
        } catch let error as ValidationError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: error.errorDescription ?? String(describing: error)
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(tokenKey, forKey: .tokenKey)
        try container.encode(localDeviceName, forKey: .localDeviceName)
    }

    public var baseURL: URL {
        validatedBaseURL
    }

    private static func makeBaseURL(host: String, port: Int) throws -> URL {
        let host = try validateHost(host)

        guard (1...65535).contains(port) else {
            throw ValidationError.invalidPort(port)
        }

        let urlHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host

        guard
            let url = URL(string: "http://\(urlHost):\(port)"),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "http",
            components.host == urlHost,
            components.port == port,
            components.path.isEmpty,
            components.query == nil,
            components.fragment == nil,
            components.user == nil,
            components.password == nil
        else {
            throw ValidationError.invalidURL(host: host, port: port)
        }

        return url
    }

    private static func validateHost(_ host: String) throws -> String {
        guard !host.isEmpty else {
            throw ValidationError.emptyHost
        }

        guard host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ValidationError.whitespaceInHost(host)
        }

        return host
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
