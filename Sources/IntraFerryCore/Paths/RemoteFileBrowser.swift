import Foundation

public protocol RemoteFileBrowsing: Sendable {
    func listDirectory(path: String) throws -> [RemoteFileEntry]
}

public struct LocalRemoteFileBrowser: RemoteFileBrowsing, @unchecked Sendable {
    typealias EntryLoader = @Sendable (URL) throws -> RemoteFileEntry

    private let pathService: AuthorizedPathService
    private let fileManager: FileManager
    private let entryLoader: EntryLoader

    public init(pathService: AuthorizedPathService, fileManager: FileManager = .default) {
        self.init(
            pathService: pathService,
            fileManager: fileManager,
            entryLoader: Self.remoteFileEntry
        )
    }

    init(
        pathService: AuthorizedPathService,
        fileManager: FileManager = .default,
        entryLoader: @escaping EntryLoader
    ) {
        self.pathService = pathService
        self.fileManager = fileManager
        self.entryLoader = entryLoader
    }

    public func listDirectory(path: String) throws -> [RemoteFileEntry] {
        try pathService.requireAuthorized(path: path)

        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FerryError.pathMissing(path)
        }

        do {
            let childURLs = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            return try childURLs
                .map(entryLoader)
                .sorted(by: compareEntries)
        } catch let error as FerryError {
            throw error
        } catch {
            throw FerryError.permissionDenied(path)
        }
    }

    private static func remoteFileEntry(for url: URL) throws -> RemoteFileEntry {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = resourceValues.isDirectory ?? false
        let size = isDirectory ? nil : resourceValues.fileSize.map(Int64.init)

        return RemoteFileEntry(
            name: url.lastPathComponent,
            path: url.standardizedFileURL.path,
            isDirectory: isDirectory,
            size: size
        )
    }

    private func compareEntries(_ lhs: RemoteFileEntry, _ rhs: RemoteFileEntry) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
