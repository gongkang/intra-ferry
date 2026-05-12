import XCTest
@testable import IntraFerryCore

final class PeerHTTPHandlerTests: XCTestCase {
    func testDirectoryRouteRejectsInvalidToken() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(root.path)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "wrong"
            ],
            body: Data()
        )

        let response = await handler.handle(request)

        XCTAssertEqual(response.statusCode, 401)
    }

    func testDirectoryRouteListsAuthorizedPath() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: root.appendingPathComponent("ok.txt"))
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let encodedPath = root.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(encodedPath)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: Data()
        )

        let response = await handler.handle(request)
        let entries = try JSONDecoder().decode([RemoteFileEntry].self, from: response.body)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(entries.map(\.name), ["ok.txt"])
    }

    func testClipboardRouteAppliesEnvelope() async throws {
        let pasteboard = FakePasteboardClient()
        let localDevice = UUID()
        let router = PeerRouter(
            localDeviceId: localDevice,
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
            receiver: nil,
            clipboard: ClipboardService(
                localDeviceId: localDevice,
                pasteboard: pasteboard,
                serializer: ClipboardSerializer(localDeviceId: localDevice)
            )
        )
        let handler = PeerHTTPHandler(router: router)
        let envelope = ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: UUID(),
            kind: .text,
            items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("remote".utf8))],
            createdAt: Date()
        )
        let request = HTTPRequest(
            method: "POST",
            path: "/clipboard",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: try JSONEncoder().encode(envelope)
        )

        let response = await handler.handle(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(pasteboard.items, envelope.items)
    }
}
