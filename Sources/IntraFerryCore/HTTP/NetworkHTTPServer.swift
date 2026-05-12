import Foundation
import Network

public final class NetworkHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let port: NWEndpoint.Port
    private let handler: Handler
    private let bodyReader = HTTPBodyReader()
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [handler, bodyReader] connection in
            connection.start(queue: .global())
            Task {
                let response: HTTPResponse
                do {
                    let data = try await bodyReader.readRequest(from: connection)
                    response = await handler(try HTTPRequest.parse(data))
                } catch {
                    response = HTTPResponse(
                        statusCode: 400,
                        headers: ["Content-Type": "text/plain"],
                        body: Data(String(describing: error).utf8)
                    )
                }

                connection.send(content: response.serialize(), completion: .contentProcessed { _ in
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
