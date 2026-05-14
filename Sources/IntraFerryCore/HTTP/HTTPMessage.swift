import Foundation

public struct HTTPRequestHead: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var initialBody: Data

    public init(method: String, path: String, headers: [String: String], initialBody: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.initialBody = initialBody
    }
}

public struct HTTPStreamRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: TransferStreamReading

    public init(method: String, path: String, headers: [String: String], body: TransferStreamReading) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public static func parse(_ data: Data) throws -> HTTPRequest {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let marker = data.range(of: delimiter) else {
            throw FerryError.pathMissing("Invalid HTTP request")
        }

        let headData = data[..<marker.lowerBound]
        let bodyData = data[marker.upperBound...]
        let head = try parseHead(Data(headData), initialBody: Data(bodyData))
        let contentLength = contentLength(from: head.headers)
        guard bodyData.count >= contentLength else {
            throw FerryError.pathMissing("HTTP body shorter than Content-Length")
        }

        return HTTPRequest(
            method: head.method,
            path: head.path,
            headers: head.headers,
            body: Data(bodyData.prefix(contentLength))
        )
    }

    public static func parseHead(_ headData: Data, initialBody: Data = Data()) throws -> HTTPRequestHead {
        let lines = String(decoding: headData, as: UTF8.self).components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw FerryError.pathMissing("Missing request line")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw FerryError.pathMissing("Invalid request line")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2 {
                headers[String(pieces[0])] = pieces[1].trimmingCharacters(in: .whitespaces)
            }
        }

        return HTTPRequestHead(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            initialBody: initialBody
        )
    }

    public static func contentLength(from headers: [String: String]) -> Int {
        headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Length") == .orderedSame
        }
        .flatMap { Int($0.value) } ?? 0
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func serialize() -> Data {
        var lines = ["HTTP/1.1 \(statusCode) \(reasonPhrase)"]
        var allHeaders = headers
        allHeaders["Connection"] = allHeaders["Connection"] ?? "close"
        allHeaders["Content-Length"] = "\(body.count)"

        for key in allHeaders.keys.sorted() {
            lines.append("\(key): \(allHeaders[key]!)")
        }
        lines.append("")
        lines.append("")

        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    private var reasonPhrase: String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Internal Server Error"
        }
    }
}
