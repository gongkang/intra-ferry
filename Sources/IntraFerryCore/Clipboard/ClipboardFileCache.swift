import Foundation

public final class ClipboardFileCache: @unchecked Sendable {
    private let cacheDirectory: URL
    private let fileManager: FileManager

    public init(cacheDirectory: URL, fileManager: FileManager = .default) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    public func cacheFilesForPasteboard(_ urls: [URL]) throws -> [ClipboardItem] {
        let batch = cacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: batch, withIntermediateDirectories: true)

        return try urls.map { source in
            let destination = batch.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            return ClipboardItem(typeIdentifier: "public.file-url", data: Data(destination.absoluteString.utf8))
        }
    }

    public func removeCacheEntries(olderThan cutoff: Date) throws {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return
        }

        let entries = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try fileManager.removeItem(at: entry)
            }
        }
    }
}
