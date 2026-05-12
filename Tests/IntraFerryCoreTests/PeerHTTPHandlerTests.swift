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
}
