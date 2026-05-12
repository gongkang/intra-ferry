import Foundation
import Network

public final class HTTPBodyReader: @unchecked Sendable {
    public init() {}

    public func readRequest(from connection: NWConnection, maximumBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        var buffer = Data()

        while true {
            let chunk = try await receiveChunk(from: connection)
            buffer.append(chunk)

            if let expectedLength = expectedRequestLength(buffer) {
                if expectedLength > maximumBytes {
                    throw FerryError.diskFull(requiredBytes: Int64(expectedLength), availableBytes: Int64(maximumBytes))
                }
                if buffer.count >= expectedLength {
                    return Data(buffer.prefix(expectedLength))
                }
            }

            if buffer.count > maximumBytes {
                throw FerryError.diskFull(requiredBytes: Int64(buffer.count), availableBytes: Int64(maximumBytes))
            }
        }
    }

    private func expectedRequestLength(_ data: Data) -> Int? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
        let headerText = String(decoding: headerData, as: UTF8.self)
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                let pieces = line.split(separator: ":", maxSplits: 1)
                guard pieces.count == 2 else {
                    return nil
                }
                return Int(pieces[1].trimmingCharacters(in: .whitespaces))
            } ?? 0

        return headerRange.upperBound + contentLength
    }

    private func receiveChunk(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: FerryError.pathMissing("Connection closed before full HTTP request"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}
