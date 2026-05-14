import Foundation
import Network

public final class NetworkHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    public typealias StreamHandler = @Sendable (HTTPStreamRequest) async -> HTTPResponse

    private let port: NWEndpoint.Port
    private let handler: Handler
    private let streamHandler: StreamHandler?
    private let bodyReader = HTTPBodyReader()
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping Handler, streamHandler: StreamHandler? = nil) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
        self.streamHandler = streamHandler
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [handler, streamHandler, bodyReader] connection in
            connection.start(queue: .global())
            Task {
                let response: HTTPResponse
                do {
                    let head = try await bodyReader.readRequestHead(from: connection)
                    if let streamHandler, head.method == "POST", head.path == "/transfers/stream" {
                        response = await streamHandler(HTTPStreamRequest(
                            method: head.method,
                            path: head.path,
                            headers: head.headers,
                            body: HTTPConnectionTransferStreamReader(initialData: head.initialBody, connection: connection)
                        ))
                    } else {
                        let body = try await bodyReader.readBody(head: head, from: connection)
                        response = await handler(HTTPRequest(
                            method: head.method,
                            path: head.path,
                            headers: head.headers,
                            body: body
                        ))
                    }
                } catch {
                    response = HTTPResponse(
                        statusCode: 400,
                        headers: ["Content-Type": "text/plain"],
                        body: Data(String(describing: error).utf8)
                    )
                }

                connection.send(content: response.serialize(), isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
