import Foundation

public final class FileTransferReceiver: @unchecked Sendable {
    private let pathService: AuthorizedPathService
    private let store: TransferReceiverStore
    private let fileManager: FileManager

    public init(pathService: AuthorizedPathService, store: TransferReceiverStore, fileManager: FileManager = .default) {
        self.pathService = pathService
        self.store = store
        self.fileManager = fileManager
    }

    public func prepare(_ manifest: TransferManifest) throws {
        try pathService.requireAuthorized(path: manifest.destinationPath)
        guard manifest.chunkSize > 0 else {
            throw FerryError.pathMissing("Chunk size must be greater than zero.")
        }

        try validateManifestPaths(manifest)
        try fileManager.createDirectory(at: store.chunksDirectory(for: manifest.transferId), withIntermediateDirectories: true)
        try store.saveState(TransferReceiverState(manifest: manifest, completedChunks: []))
    }

    public func writeChunk(transferId: UUID, fileId: String, chunkIndex: Int, data: Data) throws {
        var state = try store.loadState(transferId: transferId)
        guard let file = state.manifest.files.first(where: { $0.fileId == fileId }) else {
            throw FerryError.pathMissing("Unknown fileId \(fileId)")
        }
        guard chunkIndex >= 0, chunkIndex < file.chunkCount else {
            throw FerryError.pathMissing("Invalid chunk \(chunkIndex)")
        }

        let descriptor = chunkDescriptor(for: file, chunkIndex: chunkIndex, chunkSize: state.manifest.chunkSize)
        guard data.count == descriptor.length else {
            throw FerryError.transferIncomplete(transferId)
        }

        let chunkURL = chunkURL(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex)
        try fileManager.createDirectory(at: chunkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: chunkURL, options: [.atomic])
        state.completedChunks.insert(descriptor)
        try store.saveState(state)
    }

    public func missingChunks(transferId: UUID) throws -> [ChunkDescriptor] {
        let state = try store.loadState(transferId: transferId)
        return expectedChunks(for: state.manifest).filter { !state.completedChunks.contains($0) }
    }

    public func finalize(transferId: UUID) throws -> URL {
        let state = try store.loadState(transferId: transferId)
        guard try missingChunks(transferId: transferId).isEmpty else {
            throw FerryError.transferIncomplete(transferId)
        }

        try pathService.requireAuthorized(path: state.manifest.destinationPath)
        try validateManifestPaths(state.manifest)

        let destination = URL(fileURLWithPath: state.manifest.destinationPath, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let existingNames = Set((try? fileManager.contentsOfDirectory(atPath: destination.path)) ?? [])
        let outputName = ConflictResolver(existingNames: existingNames).availableName(for: state.manifest.rootName)
        let outputURL = destination.appendingPathComponent(outputName)

        for file in state.manifest.files {
            let target = try targetURL(for: file, manifest: state.manifest, outputURL: outputURL)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: target.path, contents: nil)

            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }

            for index in 0..<file.chunkCount {
                let data = try Data(contentsOf: chunkURL(transferId: transferId, fileId: file.fileId, chunkIndex: index))
                try handle.write(contentsOf: data)
            }
        }

        return outputURL
    }

    private func expectedChunks(for manifest: TransferManifest) -> [ChunkDescriptor] {
        manifest.files.flatMap { file in
            (0..<file.chunkCount).map { index in
                chunkDescriptor(for: file, chunkIndex: index, chunkSize: manifest.chunkSize)
            }
        }
    }

    private func chunkDescriptor(for file: TransferFileManifest, chunkIndex: Int, chunkSize: Int) -> ChunkDescriptor {
        let offset = Int64(chunkIndex * chunkSize)
        let remaining = max(file.size - offset, 0)
        return ChunkDescriptor(
            fileId: file.fileId,
            chunkIndex: chunkIndex,
            offset: offset,
            length: Int(min(Int64(chunkSize), remaining))
        )
    }

    private func targetURL(for file: TransferFileManifest, manifest: TransferManifest, outputURL: URL) throws -> URL {
        let isSingleRootFile = manifest.files.count == 1 && file.relativePath == manifest.rootName
        if isSingleRootFile {
            return outputURL
        }

        let components = try safeRelativeComponents(file.relativePath)
        return components.reduce(outputURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func validateManifestPaths(_ manifest: TransferManifest) throws {
        _ = try safeRelativeComponents(manifest.rootName)
        for file in manifest.files {
            _ = try safeRelativeComponents(file.relativePath)
        }
    }

    private func safeRelativeComponents(_ relativePath: String) throws -> [String] {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !relativePath.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw FerryError.pathOutsideAuthorizedRoots(relativePath)
        }
        return components
    }

    private func chunkURL(transferId: UUID, fileId: String, chunkIndex: Int) -> URL {
        store.chunksDirectory(for: transferId)
            .appendingPathComponent(fileId, isDirectory: true)
            .appendingPathComponent("\(chunkIndex).chunk")
    }
}
