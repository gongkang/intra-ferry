import XCTest
@testable import IntraFerryCore

final class HTTPMessageTests: XCTestCase {
    func testParsesSimpleRequest() throws {
        let raw = Data("GET /health HTTP/1.1\r\nHost: localhost\r\nX-Intra-Ferry-Token: abc\r\n\r\n".utf8)

        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/health")
        XCTAssertEqual(request.headers["X-Intra-Ferry-Token"], "abc")
        XCTAssertEqual(request.body, Data())
    }

    func testSerializesJSONResponse() {
        let response = HTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8)
        )

        let text = String(decoding: response.serialize(), as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 2\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{}"))
    }

    func testSerializedResponseAdvertisesConnectionClose() {
        let response = HTTPResponse(statusCode: 200, headers: [:], body: Data())

        let text = String(decoding: response.serialize(), as: UTF8.self)

        XCTAssertTrue(text.contains("Connection: close\r\n"))
    }

    func testSerializesForbiddenReasonPhrase() {
        let response = HTTPResponse(statusCode: 403, headers: [:], body: Data())

        let text = String(decoding: response.serialize(), as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
    }

    func testReadsBodyUsingContentLength() throws {
        let raw = Data("POST /body HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloEXTRA".utf8)

        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.body, Data("hello".utf8))
    }
}
