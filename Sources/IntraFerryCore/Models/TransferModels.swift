import Foundation

public struct TransferManifest: Codable, Equatable, Sendable {
    public var transferId: UUID
    public var destinationPath: String
    public var rootName: String
    public var files: [TransferFileManifest]
    public var chunkSize: Int

    public init(transferId: UUID, destinationPath: String, rootName: String, files: [TransferFileManifest], chunkSize: Int) {
        self.transferId = transferId
        self.destinationPath = destinationPath
        self.rootName = rootName
        self.files = files
        self.chunkSize = chunkSize
    }
}

public struct TransferFileManifest: Codable, Equatable, Sendable {
    public var fileId: String
    public var relativePath: String
    public var size: Int64
    public var chunkCount: Int

    public init(fileId: String, relativePath: String, size: Int64, chunkCount: Int) {
        self.fileId = fileId
        self.relativePath = relativePath
        self.size = size
        self.chunkCount = chunkCount
    }
}

public struct ChunkDescriptor: Codable, Equatable, Hashable, Sendable {
    public var fileId: String
    public var chunkIndex: Int
    public var offset: Int64
    public var length: Int

    public init(fileId: String, chunkIndex: Int, offset: Int64, length: Int) {
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.offset = offset
        self.length = length
    }
}

public enum TransferTaskStatus: String, Codable, Equatable, Sendable {
    case waiting
    case running
    case failed
    case completed
    case canceled
}
