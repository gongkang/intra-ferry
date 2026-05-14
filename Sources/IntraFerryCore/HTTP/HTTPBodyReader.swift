import Foundation
import Network

public final class HTTPBodyReader: @unchecked Sendable {
    public init() {}

    public func readRequest(from connection: NWConnection, maximumBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        let head = try await readRequestHead(from: connection, maximumBytes: maximumBytes)
        let body = try await readBody(head: head, from: connection, maximumBytes: maximumBytes)
        var data = serializeHead(head)
        data.append(body)
        return data
    }

    public func readRequestHead(from connection: NWConnection, maximumBytes: Int = 64 * 1024 * 1024) async throws -> HTTPRequestHead {
        var buffer = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        while true {
            let chunk = try await receiveChunk(from: connection)
            buffer.append(chunk)

            if let headerRange = buffer.range(of: delimiter) {
                let headData = buffer[..<headerRange.lowerBound]
                let initialBody = buffer[headerRange.upperBound...]
                return try HTTPRequest.parseHead(Data(headData), initialBody: Data(initialBody))
            }

            if buffer.count > maximumBytes {
                throw FerryError.diskFull(requiredBytes: Int64(buffer.count), availableBytes: Int64(maximumBytes))
            }
        }
    }

    public func readBody(head: HTTPRequestHead, from connection: NWConnection, maximumBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        let contentLength = HTTPRequest.contentLength(from: head.headers)
        if contentLength > maximumBytes {
            throw FerryError.diskFull(requiredBytes: Int64(contentLength), availableBytes: Int64(maximumBytes))
        }

        let reader = HTTPConnectionTransferStreamReader(initialData: head.initialBody, connection: connection)
        return try await reader.readExact(contentLength)
    }

    private func serializeHead(_ head: HTTPRequestHead) -> Data {
        var lines = ["\(head.method) \(head.path) HTTP/1.1"]
        for key in head.headers.keys.sorted() {
            lines.append("\(key): \(head.headers[key]!)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
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

public final class HTTPConnectionTransferStreamReader: TransferStreamReading, @unchecked Sendable {
    private var buffer: Data
    private let connection: NWConnection

    public init(initialData: Data, connection: NWConnection) {
        self.buffer = initialData
        self.connection = connection
    }

    public func readExact(_ count: Int) async throws -> Data {
        guard count >= 0 else {
            throw FerryError.pathMissing("Invalid transfer stream read length.")
        }

        while buffer.count < count {
            buffer.append(try await receiveChunk())
        }

        let data = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return data
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: FerryError.pathMissing("Connection closed before full HTTP body"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}
