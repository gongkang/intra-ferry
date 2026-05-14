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

    func testPlansHiddenFilesByDefault() throws {
        let temp = try TemporaryDirectory()
        let folder = temp.url.appendingPathComponent("Project")
        let gitDirectory = folder.appendingPathComponent(".git")
        let sourceDirectory = folder.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main".utf8).write(to: gitDirectory.appendingPathComponent("HEAD"))
        try Data("print(1)".utf8).write(to: sourceDirectory.appendingPathComponent("main.swift"))
        let planner = TransferPlanner(chunkSize: 16)

        let plan = try planner.plan(items: [folder], destinationPath: "/Users/task/inbox")

        XCTAssertEqual(plan.manifest.files.map(\.relativePath), [".git/HEAD", "Sources/main.swift"])
    }

    func testCanSkipHiddenFilesWhenPlanningFolder() throws {
        let temp = try TemporaryDirectory()
        let folder = temp.url.appendingPathComponent("Project")
        let gitDirectory = folder.appendingPathComponent(".git")
        let sourceDirectory = folder.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main".utf8).write(to: gitDirectory.appendingPathComponent("HEAD"))
        try Data("print(1)".utf8).write(to: sourceDirectory.appendingPathComponent("main.swift"))
        let planner = TransferPlanner(chunkSize: 16, includesHiddenFiles: false)

        let plan = try planner.plan(items: [folder], destinationPath: "/Users/task/inbox")

        XCTAssertEqual(plan.manifest.files.map(\.relativePath), ["Sources/main.swift"])
    }

    func testPlansMultipleFoldersUnderDistinctTopLevelNames() throws {
        let temp = try TemporaryDirectory()
        let firstProject = temp.url.appendingPathComponent("One/Project")
        let secondProject = temp.url.appendingPathComponent("Two/Project")
        try FileManager.default.createDirectory(at: firstProject.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProject.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstProject.appendingPathComponent("Sources/main.swift"))
        try Data("second".utf8).write(to: secondProject.appendingPathComponent("Sources/main.swift"))
        let planner = TransferPlanner(chunkSize: 16)

        let plan = try planner.plan(items: [firstProject, secondProject], destinationPath: "/Users/task/inbox")

        XCTAssertTrue(plan.manifest.rootName.hasPrefix("Transfer "))
        XCTAssertEqual(
            plan.manifest.files.map(\.relativePath),
            ["Project copy/Sources/main.swift", "Project/Sources/main.swift"]
        )
        XCTAssertEqual(Set(plan.manifest.files.map(\.fileId)).count, 2)
        XCTAssertEqual(Set(plan.sourceFiles.values.map(canonicalPath)), Set([
            canonicalPath(firstProject.appendingPathComponent("Sources/main.swift")),
            canonicalPath(secondProject.appendingPathComponent("Sources/main.swift"))
        ]))
    }

    func testPlansMultipleFilesWithDuplicateNamesWithoutOverwritingSources() throws {
        let temp = try TemporaryDirectory()
        let first = temp.url.appendingPathComponent("One/report.txt")
        let second = temp.url.appendingPathComponent("Two/report.txt")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("same".utf8).write(to: first)
        try Data("same".utf8).write(to: second)
        let planner = TransferPlanner(chunkSize: 16)

        let plan = try planner.plan(items: [first, second], destinationPath: "/Users/task/inbox")

        XCTAssertEqual(plan.manifest.files.map(\.relativePath), ["report copy.txt", "report.txt"])
        XCTAssertEqual(Set(plan.manifest.files.map(\.fileId)).count, 2)
        XCTAssertEqual(Set(plan.sourceFiles.values.map(canonicalPath)), Set([canonicalPath(first), canonicalPath(second)]))
    }

    func testConflictResolverCreatesCopyName() {
        let resolver = ConflictResolver(existingNames: Set(["data", "data copy", "notes.txt"]))

        XCTAssertEqual(resolver.availableName(for: "data"), "data copy 2")
        XCTAssertEqual(resolver.availableName(for: "notes.txt"), "notes copy.txt")
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}
