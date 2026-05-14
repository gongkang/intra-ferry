import Foundation

public protocol TransferStreamReading: Sendable {
    func readExact(_ count: Int) async throws -> Data
}

public final class DataTransferStreamReader: TransferStreamReading, @unchecked Sendable {
    private let data: Data
    private var offset = 0

    public init(data: Data) {
        self.data = data
    }

    public func readExact(_ count: Int) async throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw FerryError.pathMissing("Transfer stream ended unexpectedly.")
        }

        let chunk = data[offset..<offset + count]
        offset += count
        return Data(chunk)
    }
}

public enum TransferStreamFrame: Equatable, Sendable {
    case chunk(fileId: String, chunkIndex: Int, data: Data)
    case end
}

public struct TransferStreamEncoder: Sendable {
    private static let magic = Data("IFST1".utf8)
    private static let chunkFrame = UInt8(1)
    private static let endFrame = UInt8(255)

    public static func write(plan: TransferPlan, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.write(contentsOf: magic)
        let manifestData = try JSONEncoder().encode(plan.manifest)
        try handle.write(contentsOf: encodeUInt32(UInt32(manifestData.count)))
        try handle.write(contentsOf: manifestData)

        for chunk in plan.chunks {
            guard let fileURL = plan.sourceFiles[chunk.fileId] else {
                throw FerryError.pathMissing(chunk.fileId)
            }

            let data = try readChunk(fileURL: fileURL, descriptor: chunk, transferId: plan.manifest.transferId)
            let fileIdData = Data(chunk.fileId.utf8)
            guard fileIdData.count <= Int(UInt16.max) else {
                throw FerryError.pathMissing("File id is too long.")
            }

            try handle.write(contentsOf: Data([chunkFrame]))
            try handle.write(contentsOf: encodeUInt16(UInt16(fileIdData.count)))
            try handle.write(contentsOf: fileIdData)
            try handle.write(contentsOf: encodeUInt32(UInt32(chunk.chunkIndex)))
            try handle.write(contentsOf: encodeUInt64(UInt64(data.count)))
            try handle.write(contentsOf: data)
        }

        try handle.write(contentsOf: Data([endFrame]))
    }

    private static func readChunk(fileURL: URL, descriptor: ChunkDescriptor, transferId: UUID) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(descriptor.offset))
        let data = try handle.read(upToCount: descriptor.length) ?? Data()
        guard data.count == descriptor.length else {
            throw FerryError.transferIncomplete(transferId)
        }
        return data
    }

    private static func encodeUInt16(_ value: UInt16) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt16>.size)
    }

    private static func encodeUInt32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }

    private static func encodeUInt64(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
    }
}

public final class TransferStreamDecoder: @unchecked Sendable {
    private static let magic = Data("IFST1".utf8)
    private static let chunkFrame = UInt8(1)
    private static let endFrame = UInt8(255)
    private static let maxManifestBytes = 1 * 1024 * 1024

    private let reader: TransferStreamReading
    private var didReadManifest = false
    private var manifest: TransferManifest?
    private var expectedChunkLengths: [ChunkKey: Int] = [:]

    public init(reader: TransferStreamReading) {
        self.reader = reader
    }

    public func readManifest() async throws -> TransferManifest {
        guard !didReadManifest else {
            throw FerryError.pathMissing("Transfer stream manifest was already read.")
        }

        let magic = try await reader.readExact(Self.magic.count)
        guard magic == Self.magic else {
            throw FerryError.pathMissing("Invalid transfer stream.")
        }

        let manifestLength = try await readUInt32()
        guard manifestLength <= Self.maxManifestBytes else {
            throw FerryError.pathMissing("Transfer stream manifest is too large.")
        }

        let manifestData = try await reader.readExact(Int(manifestLength))
        let manifest = try JSONDecoder().decode(TransferManifest.self, from: manifestData)
        expectedChunkLengths = try buildExpectedChunkLengths(for: manifest)
        self.manifest = manifest
        didReadManifest = true
        return manifest
    }

    public func readFrame() async throws -> TransferStreamFrame {
        guard didReadManifest else {
            throw FerryError.pathMissing("Transfer stream manifest must be read before frames.")
        }

        let type = try await reader.readExact(1)[0]
        switch type {
        case Self.endFrame:
            return .end
        case Self.chunkFrame:
            let fileIdLength = try await readUInt16()
            let fileIdData = try await reader.readExact(Int(fileIdLength))
            guard let fileId = String(data: fileIdData, encoding: .utf8) else {
                throw FerryError.pathMissing("Invalid transfer stream file id.")
            }
            let chunkIndex = try await readUInt32()
            let dataLength = try await readUInt64()
            let chunkKey = ChunkKey(fileId: fileId, chunkIndex: Int(chunkIndex))
            guard let expectedLength = expectedChunkLengths[chunkKey] else {
                if expectedChunkLengths.keys.contains(where: { $0.fileId == fileId }) {
                    throw FerryError.pathMissing("Invalid chunk \(chunkIndex)")
                }
                throw FerryError.pathMissing("Unknown fileId \(fileId)")
            }
            guard dataLength == UInt64(expectedLength) else {
                throw FerryError.transferIncomplete(manifest?.transferId ?? UUID())
            }
            let data = try await reader.readExact(Int(dataLength))
            return .chunk(fileId: fileId, chunkIndex: Int(chunkIndex), data: data)
        default:
            throw FerryError.pathMissing("Invalid transfer stream frame type \(type).")
        }
    }

    private struct ChunkKey: Hashable {
        var fileId: String
        var chunkIndex: Int
    }

    private func buildExpectedChunkLengths(for manifest: TransferManifest) throws -> [ChunkKey: Int] {
        guard manifest.chunkSize > 0 else {
            throw FerryError.pathMissing("Chunk size must be greater than zero.")
        }

        var fileIds = Set<String>()
        var expectedLengths: [ChunkKey: Int] = [:]
        for file in manifest.files {
            guard !file.fileId.isEmpty else {
                throw FerryError.pathMissing("Transfer stream file id is empty.")
            }
            guard fileIds.insert(file.fileId).inserted else {
                throw FerryError.pathMissing("Duplicate transfer stream file id \(file.fileId).")
            }
            guard file.size >= 0, file.chunkCount >= 0 else {
                throw FerryError.pathMissing("Invalid transfer stream file manifest.")
            }
            let chunkSize = Int64(manifest.chunkSize)
            let expectedChunkCount = file.size == 0 ? 0 : Int(((file.size - 1) / chunkSize) + 1)
            guard file.chunkCount == expectedChunkCount else {
                throw FerryError.transferIncomplete(manifest.transferId)
            }

            for chunkIndex in 0..<file.chunkCount {
                let offset = Int64(chunkIndex) * Int64(manifest.chunkSize)
                let remaining = max(file.size - offset, 0)
                expectedLengths[ChunkKey(fileId: file.fileId, chunkIndex: chunkIndex)] = Int(min(Int64(manifest.chunkSize), remaining))
            }
        }
        return expectedLengths
    }

    private func readUInt16() async throws -> UInt16 {
        let data = try await reader.readExact(MemoryLayout<UInt16>.size)
        return data.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    private func readUInt32() async throws -> UInt32 {
        let data = try await reader.readExact(MemoryLayout<UInt32>.size)
        return data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func readUInt64() async throws -> UInt64 {
        let data = try await reader.readExact(MemoryLayout<UInt64>.size)
        return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
