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

    public func streamTransfer(peer: PeerConfig, token: AuthToken, plan: TransferPlan) async throws -> String {
        let payloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("intra-ferry-\(plan.manifest.transferId.uuidString).stream")
        defer { try? FileManager.default.removeItem(at: payloadURL) }

        try TransferStreamEncoder.write(plan: plan, to: payloadURL)
        let url = peer.baseURL.appendingPathComponent("transfers").appendingPathComponent("stream")
        let data = try await uploadFile(for: url, peer: peer, token: token, fileURL: payloadURL)
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

    private func uploadFile(for url: URL, peer: PeerConfig, token: AuthToken, fileURL: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyPeerHeaders(to: &request, peer: peer, token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch let error as URLError where Self.isOffline(error) {
            throw FerryError.peerOffline(host: peer.host, port: peer.port)
        } catch {
            throw FerryError.peerRequestFailed(host: peer.host, port: peer.port, reason: error.localizedDescription)
        }

        return try validatedResponseData(data, response: response)
    }

    private func data(
        for url: URL,
        peer: PeerConfig,
        token: AuthToken,
        method: String,
        body: Data?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyPeerHeaders(to: &request, peer: peer, token: token)
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

        return try validatedResponseData(data, response: response)
    }

    private func applyPeerHeaders(to request: inout URLRequest, peer: PeerConfig, token: AuthToken) {
        request.setValue(IntraFerryCore.protocolVersion, forHTTPHeaderField: "X-Intra-Ferry-Protocol")
        request.setValue(peer.localDeviceName, forHTTPHeaderField: "X-Intra-Ferry-Device-Name")
        request.setValue(peer.id.uuidString, forHTTPHeaderField: "X-Intra-Ferry-Device-Id")
        request.setValue(token.rawValue, forHTTPHeaderField: "X-Intra-Ferry-Token")
        request.setValue("close", forHTTPHeaderField: "Connection")
    }

    private func validatedResponseData(_ data: Data, response: URLResponse) throws -> Data {
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
