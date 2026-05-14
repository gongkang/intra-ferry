import Foundation

public final class PeerHTTPHandler: @unchecked Sendable {
    private let router: PeerRouter

    public init(router: PeerRouter) {
        self.router = router
    }

    public func handleStream(_ request: HTTPStreamRequest) async -> HTTPResponse {
        do {
            let peerRequest = try peerRequest(
                headers: request.headers,
                missingDeviceMessage: "Missing X-Intra-Ferry-Device-Id"
            )
            guard request.method == "POST", pathOnly(request.path) == "/transfers/stream" else {
                return HTTPResponse(statusCode: 404, headers: [:], body: Data("Not found".utf8))
            }
            try router.authenticate(peerRequest)

            let decoder = TransferStreamDecoder(reader: request.body)
            let manifest = try await decoder.readManifest()
            let finalURL = try await router.receiveTransferStream(manifest: manifest, decoder: decoder, request: peerRequest)
            return HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "text/plain"],
                body: Data((finalURL?.path ?? "").utf8)
            )
        } catch FerryError.invalidToken {
            return HTTPResponse(statusCode: 401, headers: [:], body: Data("Invalid token".utf8))
        } catch let FerryError.pathOutsideAuthorizedRoots(path) {
            return HTTPResponse(statusCode: 403, headers: [:], body: Data(path.utf8))
        } catch let FerryError.permissionDenied(path) {
            return HTTPResponse(statusCode: 403, headers: [:], body: Data(path.utf8))
        } catch let FerryError.pathMissing(path) {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(path.utf8))
        } catch {
            return HTTPResponse(statusCode: 400, headers: [:], body: Data(String(describing: error).utf8))
        }
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let peerRequest = try peerRequest(from: request)
            switch (request.method, pathOnly(request.path)) {
            case ("GET", "/roots"):
                let roots = try router.listAuthorizedRoots(request: peerRequest)
                return try json(roots)

            case ("GET", "/directories"):
                let path = try queryValue("path", in: request.path)
                let entries = try router.listDirectory(path: path, request: peerRequest)
                return try json(entries)

            case ("POST", "/clipboard"):
                let envelope = try JSONDecoder().decode(ClipboardEnvelope.self, from: request.body)
                try router.applyClipboard(envelope, request: peerRequest)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())

            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data("Not found".utf8))
            }
        } catch FerryError.invalidToken {
            return HTTPResponse(statusCode: 401, headers: [:], body: Data("Invalid token".utf8))
        } catch let FerryError.pathOutsideAuthorizedRoots(path) {
            return HTTPResponse(statusCode: 403, headers: [:], body: Data(path.utf8))
        } catch let FerryError.permissionDenied(path) {
            return HTTPResponse(statusCode: 403, headers: [:], body: Data(path.utf8))
        } catch let FerryError.pathMissing(path) {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(path.utf8))
        } catch {
            return HTTPResponse(statusCode: 400, headers: [:], body: Data(String(describing: error).utf8))
        }
    }

    private func peerRequest(from request: HTTPRequest) throws -> PeerRequest {
        try peerRequest(headers: request.headers, missingDeviceMessage: "Missing X-Intra-Ferry-Device-Id")
    }

    private func peerRequest(headers: [String: String], missingDeviceMessage: String) throws -> PeerRequest {
        guard let id = headers["X-Intra-Ferry-Device-Id"].flatMap(UUID.init(uuidString:)) else {
            throw FerryError.pathMissing(missingDeviceMessage)
        }
        return PeerRequest(
            deviceId: id,
            protocolVersion: headers["X-Intra-Ferry-Protocol"] ?? "",
            token: AuthToken(rawValue: headers["X-Intra-Ferry-Token"] ?? "")
        )
    }

    private func json<T: Encodable>(_ value: T) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(value)
        )
    }

    private func pathOnly(_ path: String) -> String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }

    private func queryValue(_ name: String, in path: String) throws -> String {
        guard let components = URLComponents(string: "http://localhost\(path)"),
              let value = components.queryItems?.first(where: { $0.name == name })?.value else {
            throw FerryError.pathMissing("Missing query item \(name)")
        }
        return value
    }
}
