import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionPeerClient: PeerClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func listAuthorizedRoots(peer: PeerConfig, token: AuthToken) async throws -> [AuthorizedRoot] {
        let data = try await data(
            for: peer.baseURL.appendingPathComponent("roots"),
            peer: peer,
            token: token,
            method: "GET",
            body: nil
        )
        return try JSONDecoder().decode([AuthorizedRoot].self, from: data)
    }

    public func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry] {
        var components = URLComponents(url: peer.baseURL.appendingPathComponent("directories"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        let data = try await data(for: components.url!, peer: peer, token: token, method: "GET", body: nil)
        return try JSONDecoder().decode([RemoteFileEntry].self, from: data)
    }

    public func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws {
        let body = try JSONEncoder().encode(manifest)
        _ = try await data(
            for: peer.baseURL.appendingPathComponent("transfers"),
            peer: peer,
            token: token,
            method: "POST",
            body: body
        )
    }

    public func uploadChunk(
        peer: PeerConfig,
        token: AuthToken,
        transferId: UUID,
        fileId: String,
        chunkIndex: Int,
        data: Data
    ) async throws {
        let url = peer.baseURL
            .appendingPathComponent("transfers")
            .appendingPathComponent(transferId.uuidString)
            .appendingPathComponent("files")
            .appendingPathComponent(fileId)
            .appendingPathComponent("chunks")
            .appendingPathComponent("\(chunkIndex)")
        _ = try await self.data(for: url, peer: peer, token: token, method: "PUT", body: data)
    }

    public func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String {
        let url = peer.baseURL
            .appendingPathComponent("transfers")
            .appendingPathComponent(transferId.uuidString)
            .appendingPathComponent("finalize")
        let data = try await data(for: url, peer: peer, token: token, method: "POST", body: nil)
        return String(decoding: data, as: UTF8.self)
    }

    public func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws {
        let body = try JSONEncoder().encode(envelope)
        _ = try await data(
            for: peer.baseURL.appendingPathComponent("clipboard"),
            peer: peer,
            token: token,
            method: "POST",
            body: body
        )
    }

    private func data(for url: URL, peer: PeerConfig, token: AuthToken, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(IntraFerryCore.protocolVersion, forHTTPHeaderField: "X-Intra-Ferry-Protocol")
        request.setValue(peer.localDeviceName, forHTTPHeaderField: "X-Intra-Ferry-Device-Name")
        request.setValue(peer.id.uuidString, forHTTPHeaderField: "X-Intra-Ferry-Device-Id")
        request.setValue(token.rawValue, forHTTPHeaderField: "X-Intra-Ferry-Token")
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.isOffline(error) {
            throw FerryError.peerOffline(host: peer.host, port: peer.port)
        } catch {
            throw FerryError.peerRequestFailed(host: peer.host, port: peer.port, reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(decoding: data, as: UTF8.self)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            switch statusCode {
            case 401:
                throw FerryError.invalidToken
            case 403:
                throw FerryError.permissionDenied(message)
            case 404:
                throw FerryError.pathMissing(message)
            default:
                throw FerryError.permissionDenied(message.isEmpty ? "HTTP \(statusCode ?? 0)" : message)
            }
        }
        return data
    }

    private static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
