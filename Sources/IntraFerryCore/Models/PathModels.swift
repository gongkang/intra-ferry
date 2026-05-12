import Foundation

public struct AuthorizedRoot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var path: String

    public init(id: UUID, displayName: String, path: String) {
        self.id = id
        self.displayName = displayName
        self.path = path
    }
}

public struct RemoteFileEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int64?

    public init(name: String, path: String, isDirectory: Bool, size: Int64?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
    }
}
