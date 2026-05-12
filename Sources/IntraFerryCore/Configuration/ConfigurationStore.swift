import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var localDevice: LocalDeviceConfig
    public var peers: [PeerConfig]
    public var authorizedRoots: [AuthorizedRoot]
    public var clipboardSyncEnabled: Bool
    public var stagingDirectoryPath: String

    public init(
        localDevice: LocalDeviceConfig,
        peers: [PeerConfig],
        authorizedRoots: [AuthorizedRoot],
        clipboardSyncEnabled: Bool,
        stagingDirectoryPath: String
    ) {
        self.localDevice = localDevice
        self.peers = peers
        self.authorizedRoots = authorizedRoots
        self.clipboardSyncEnabled = clipboardSyncEnabled
        self.stagingDirectoryPath = stagingDirectoryPath
    }
}

public protocol ConfigurationStore: Sendable {
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

public final class FileConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try makeDecoder().decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let data = try makeEncoder().encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
