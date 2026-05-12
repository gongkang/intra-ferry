import Foundation

public struct TransferReceiverState: Codable, Equatable, Sendable {
    public var manifest: TransferManifest
    public var completedChunks: Set<ChunkDescriptor>

    public init(manifest: TransferManifest, completedChunks: Set<ChunkDescriptor>) {
        self.manifest = manifest
        self.completedChunks = completedChunks
    }
}

public final class TransferReceiverStore: @unchecked Sendable {
    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func taskDirectory(for transferId: UUID) -> URL {
        baseDirectory.appendingPathComponent(transferId.uuidString, isDirectory: true)
    }

    public func chunksDirectory(for transferId: UUID) -> URL {
        taskDirectory(for: transferId).appendingPathComponent("chunks", isDirectory: true)
    }

    public func loadState(transferId: UUID) throws -> TransferReceiverState {
        let url = taskDirectory(for: transferId).appendingPathComponent("state.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TransferReceiverState.self, from: data)
    }

    public func saveState(_ state: TransferReceiverState) throws {
        let directory = taskDirectory(for: state.manifest.transferId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: directory.appendingPathComponent("state.json"), options: [.atomic])
    }
}
