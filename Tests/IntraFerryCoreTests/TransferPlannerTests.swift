import XCTest
@testable import IntraFerryCore

final class TransferPlannerTests: XCTestCase {
    func testPlansSingleFileChunks() throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("sample.bin")
        try Data(repeating: 7, count: 10).write(to: file)
        let planner = TransferPlanner(chunkSize: 4)

        let plan = try planner.plan(items: [file], destinationPath: "/Users/task/inbox")

        XCTAssertEqual(plan.manifest.rootName, "sample.bin")
        XCTAssertEqual(plan.manifest.files.count, 1)
        XCTAssertEqual(plan.manifest.files[0].chunkCount, 3)
        XCTAssertEqual(plan.chunks.map(\.length), [4, 4, 2])
    }

    func testPlansFolderWithRelativePaths() throws {
        let temp = try TemporaryDirectory()
        let folder = temp.url.appendingPathComponent("Project")
        let nested = folder.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("print(1)".utf8).write(to: nested.appendingPathComponent("main.swift"))
        let planner = TransferPlanner(chunkSize: 16)

        let plan = try planner.plan(items: [folder], destinationPath: "/Users/task/inbox")

        XCTAssertEqual(plan.manifest.rootName, "Project")
        XCTAssertEqual(plan.manifest.files.map(\.relativePath), ["Sources/main.swift"])
    }

    func testConflictResolverCreatesCopyName() {
        let resolver = ConflictResolver(existingNames: Set(["data", "data copy", "notes.txt"]))

        XCTAssertEqual(resolver.availableName(for: "data"), "data copy 2")
        XCTAssertEqual(resolver.availableName(for: "notes.txt"), "notes copy.txt")
    }
}
