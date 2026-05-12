import Foundation

public enum ClipboardContentKind: String, Codable, Equatable, Sendable {
    case text
    case image
    case fileURLs
    case unsupported
}

public struct ClipboardEnvelope: Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceDeviceId: UUID
    public var kind: ClipboardContentKind
    public var items: [ClipboardItem]
    public var createdAt: Date

    public init(id: UUID, sourceDeviceId: UUID, kind: ClipboardContentKind, items: [ClipboardItem], createdAt: Date) {
        self.id = id
        self.sourceDeviceId = sourceDeviceId
        self.kind = kind
        self.items = items
        self.createdAt = createdAt
    }
}

public struct ClipboardItem: Codable, Equatable, Sendable {
    public var typeIdentifier: String
    public var data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}
