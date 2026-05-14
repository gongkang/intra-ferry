import XCTest
@testable import IntraFerryCore

final class TransferStreamCodecTests: XCTestCase {
    func testEncoderAndDecoderRoundTripManifestChunksAndEndFrame() async throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("hello.txt")
        try Data("HelloWorld".utf8).write(to: source)
        let plan = try TransferPlanner(chunkSize: 5).plan(items: [source], destinationPath: "/Users/task/inbox")
        let payloadURL = temp.url.appendingPathComponent("stream.bin")

        try TransferStreamEncoder.write(plan: plan, to: payloadURL)
        let reader = DataTransferStreamReader(data: try Data(contentsOf: payloadURL))
        let decoder = TransferStreamDecoder(reader: reader)

        let manifest = try await decoder.readManifest()
        let first = try await decoder.readFrame()
        let second = try await decoder.readFrame()
        let end = try await decoder.readFrame()

        XCTAssertEqual(manifest, plan.manifest)
        XCTAssertEqual(first, .chunk(fileId: plan.chunks[0].fileId, chunkIndex: 0, data: Data("Hello".utf8)))
        XCTAssertEqual(second, .chunk(fileId: plan.chunks[1].fileId, chunkIndex: 1, data: Data("World".utf8)))
        XCTAssertEqual(end, .end)
    }

    func testDecoderRejectsOversizedManifestBeforeReadingBody() async throws {
        var payload = Data("IFST1".utf8)
        payload.append(encodeUInt32(1_048_577))
        let reader = RecordingTransferStreamReader(data: payload)
        let decoder = TransferStreamDecoder(reader: reader)

        do {
            _ = try await decoder.readManifest()
            XCTFail("Expected oversized manifest to be rejected")
        } catch {
            guard case .pathMissing = error as? FerryError else {
                return XCTFail("Expected pathMissing, got \(error)")
            }
        }

        XCTAssertFalse(reader.requestedCounts.contains { $0 > 1_048_576 })
    }

    func testDecoderRejectsUnexpectedChunkLengthBeforeReadingPayload() async throws {
        let manifest = TransferManifest(
            transferId: UUID(),
            destinationPath: "/Users/task/inbox",
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: "hello", relativePath: "hello.txt", size: 4, chunkCount: 1)],
            chunkSize: 4
        )
        let reader = RecordingTransferStreamReader(data: try streamPayload(
            manifest: manifest,
            fileId: "hello",
            chunkIndex: 0,
            declaredDataLength: 1_048_577
        ))
        let decoder = TransferStreamDecoder(reader: reader)
        _ = try await decoder.readManifest()

        do {
            _ = try await decoder.readFrame()
            XCTFail("Expected chunk with unexpected length to be rejected")
        } catch {
            guard case .transferIncomplete = error as? FerryError else {
                return XCTFail("Expected transferIncomplete, got \(error)")
            }
        }

        XCTAssertFalse(reader.requestedCounts.contains { $0 > 1_048_576 })
    }

    func testDecoderRejectsUnknownChunkFileBeforeReadingPayload() async throws {
        let manifest = TransferManifest(
            transferId: UUID(),
            destinationPath: "/Users/task/inbox",
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: "hello", relativePath: "hello.txt", size: 4, chunkCount: 1)],
            chunkSize: 4
        )
        let reader = RecordingTransferStreamReader(data: try streamPayload(
            manifest: manifest,
            fileId: "unknown",
            chunkIndex: 0,
            declaredDataLength: 1_048_577
        ))
        let decoder = TransferStreamDecoder(reader: reader)
        _ = try await decoder.readManifest()

        do {
            _ = try await decoder.readFrame()
            XCTFail("Expected unknown chunk file to be rejected")
        } catch {
            guard case .pathMissing = error as? FerryError else {
                return XCTFail("Expected pathMissing, got \(error)")
            }
        }

        XCTAssertFalse(reader.requestedCounts.contains { $0 > 1_048_576 })
    }

    private func streamPayload(
        manifest: TransferManifest,
        fileId: String,
        chunkIndex: UInt32,
        declaredDataLength: UInt64
    ) throws -> Data {
        let manifestData = try JSONEncoder().encode(manifest)
        var payload = Data("IFST1".utf8)
        payload.append(encodeUInt32(UInt32(manifestData.count)))
        payload.append(manifestData)
        let fileIdData = Data(fileId.utf8)
        payload.append(1)
        payload.append(encodeUInt16(UInt16(fileIdData.count)))
        payload.append(fileIdData)
        payload.append(encodeUInt32(chunkIndex))
        payload.append(encodeUInt64(declaredDataLength))
        return payload
    }

    private func encodeUInt16(_ value: UInt16) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt16>.size)
    }

    private func encodeUInt32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }

    private func encodeUInt64(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
    }
}

private final class RecordingTransferStreamReader: TransferStreamReading, @unchecked Sendable {
    private let data: Data
    private var offset = 0
    private(set) var requestedCounts: [Int] = []

    init(data: Data) {
        self.data = data
    }

    func readExact(_ count: Int) async throws -> Data {
        requestedCounts.append(count)
        guard count >= 0, offset + count <= data.count else {
            throw FerryError.pathMissing("Transfer stream ended unexpectedly.")
        }

        let chunk = data[offset..<offset + count]
        offset += count
        return Data(chunk)
    }
}
