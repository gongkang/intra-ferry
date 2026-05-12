import Foundation
import XCTest
@testable import IntraFerryCore

final class PeerRouterTests: XCTestCase {
    func testRejectsInvalidTokenBeforeDirectoryListing() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "correct"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )

        XCTAssertThrowsError(
            try router.listDirectory(
                path: root.path,
                request: PeerRequest(
                    deviceId: UUID(),
                    protocolVersion: "1",
                    token: AuthToken(rawValue: "wrong")
                )
            )
        ) { error in
            XCTAssertEqual(error as? FerryError, .invalidToken)
        }
    }

    func testListsDirectoryWithValidToken() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: root.appendingPathComponent("ok.txt"))
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "correct"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )

        let entries = try router.listDirectory(
            path: root.path,
            request: PeerRequest(
                deviceId: UUID(),
                protocolVersion: "1",
                token: AuthToken(rawValue: "correct")
            )
        )

        XCTAssertEqual(entries.map(\.name), ["ok.txt"])
    }

    func testRejectsUnsupportedProtocolVersion() throws {
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "correct"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
            receiver: nil
        )

        XCTAssertThrowsError(
            try router.authenticate(
                PeerRequest(
                    deviceId: UUID(),
                    protocolVersion: "99",
                    token: AuthToken(rawValue: "correct")
                )
            )
        ) { error in
            XCTAssertEqual(error as? FerryError, .unsupportedProtocolVersion("99"))
        }
    }
}
