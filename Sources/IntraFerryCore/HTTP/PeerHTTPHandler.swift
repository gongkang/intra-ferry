import Foundation

public final class PeerHTTPHandler: @unchecked Sendable {
    private let router: PeerRouter

    public init(router: PeerRouter) {
        self.router = router
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

            case ("POST", "/transfers"):
                let manifest = try JSONDecoder().decode(TransferManifest.self, from: request.body)
                try router.prepareTransfer(manifest, request: peerRequest)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())

            case ("PUT", let path) where isChunkPath(path):
                let route = try parseChunkRoute(path)
                try router.writeChunk(
                    transferId: route.transferId,
                    fileId: route.fileId,
                    chunkIndex: route.chunkIndex,
                    data: request.body,
                    request: peerRequest
                )
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())

            case ("POST", let path) where path.hasSuffix("/finalize"):
                let transferId = try parseFinalizeRoute(path)
                let finalURL = try router.finalizeTransfer(transferId: transferId, request: peerRequest)
                return HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/plain"],
                    body: Data((finalURL?.path ?? "").utf8)
                )

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
        guard let id = request.headers["X-Intra-Ferry-Device-Id"].flatMap(UUID.init(uuidString:)) else {
            throw FerryError.pathMissing("Missing X-Intra-Ferry-Device-Id")
        }

        return PeerRequest(
            deviceId: id,
            protocolVersion: request.headers["X-Intra-Ferry-Protocol"] ?? "",
            token: AuthToken(rawValue: request.headers["X-Intra-Ferry-Token"] ?? "")
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

    private func isChunkPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count == 6 && parts[0] == "transfers" && parts[2] == "files" && parts[4] == "chunks"
    }

    private func parseChunkRoute(_ path: String) throws -> (transferId: UUID, fileId: String, chunkIndex: Int) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 6,
              parts[0] == "transfers",
              let transferId = UUID(uuidString: parts[1]),
              parts[2] == "files",
              parts[4] == "chunks",
              let chunkIndex = Int(parts[5]) else {
            throw FerryError.pathMissing("Invalid chunk route \(path)")
        }
        return (transferId, parts[3], chunkIndex)
    }

    private func parseFinalizeRoute(_ path: String) throws -> UUID {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3,
              parts[0] == "transfers",
              let transferId = UUID(uuidString: parts[1]),
              parts[2] == "finalize" else {
            throw FerryError.pathMissing("Invalid finalize route \(path)")
        }
        return transferId
    }
}
