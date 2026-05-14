import CryptoKit
import Foundation

public struct TransferPlan: Equatable, Sendable {
    public var manifest: TransferManifest
    public var sourceFiles: [String: URL]
    public var chunks: [ChunkDescriptor]

    public init(manifest: TransferManifest, sourceFiles: [String: URL], chunks: [ChunkDescriptor]) {
        self.manifest = manifest
        self.sourceFiles = sourceFiles
        self.chunks = chunks
    }
}

public struct TransferPlanner: @unchecked Sendable {
    public var chunkSize: Int

    private let fileManager: FileManager
    private let includesHiddenFiles: Bool

    public init(
        chunkSize: Int = 16 * 1024 * 1024,
        includesHiddenFiles: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.chunkSize = chunkSize
        self.includesHiddenFiles = includesHiddenFiles
        self.fileManager = fileManager
    }

    public func plan(items: [URL], destinationPath: String) throws -> TransferPlan {
        guard let first = items.first else {
            throw FerryError.pathMissing("No transfer items were provided.")
        }
        guard chunkSize > 0 else {
            throw FerryError.pathMissing("Chunk size must be greater than zero.")
        }

        let rootName = items.count == 1 ? first.lastPathComponent : "Transfer \(UUID().uuidString)"
        var files: [TransferFileManifest] = []
        var sourceFiles: [String: URL] = [:]
        var chunks: [ChunkDescriptor] = []

        let plannedItems = try planTopLevelItems(items)
        for plannedItem in plannedItems {
            let itemFiles = try enumerateFiles(plannedItem.url)
            let itemIsDirectory = try isDirectory(plannedItem.url)
            for file in itemFiles {
                let relativePath = try relativePath(for: file, base: plannedItem.url)
                let destinationRelativePath = destinationRelativePath(
                    relativePath: relativePath,
                    topLevelName: plannedItem.topLevelName,
                    itemIsDirectory: itemIsDirectory,
                    includeTopLevelName: items.count > 1
                )
                let size = try fileSize(file)
                let fileId = stableFileId(relativePath: destinationRelativePath, size: size)
                let chunkCount = Int((size + Int64(chunkSize) - 1) / Int64(chunkSize))

                files.append(
                    TransferFileManifest(
                        fileId: fileId,
                        relativePath: destinationRelativePath,
                        size: size,
                        chunkCount: chunkCount
                    )
                )
                sourceFiles[fileId] = file

                for index in 0..<chunkCount {
                    let offset = Int64(index * chunkSize)
                    let remaining = size - offset
                    chunks.append(
                        ChunkDescriptor(
                            fileId: fileId,
                            chunkIndex: index,
                            offset: offset,
                            length: Int(min(Int64(chunkSize), remaining))
                        )
                    )
                }
            }
        }

        return TransferPlan(
            manifest: TransferManifest(
                transferId: UUID(),
                destinationPath: destinationPath,
                rootName: rootName,
                files: files.sorted { $0.relativePath < $1.relativePath },
                chunkSize: chunkSize
            ),
            sourceFiles: sourceFiles,
            chunks: chunks.sorted { lhs, rhs in
                lhs.fileId == rhs.fileId ? lhs.chunkIndex < rhs.chunkIndex : lhs.fileId < rhs.fileId
            }
        )
    }

    private struct PlannedTopLevelItem {
        var url: URL
        var topLevelName: String
    }

    private func planTopLevelItems(_ items: [URL]) throws -> [PlannedTopLevelItem] {
        var reservedNames = Set<String>()
        return items.map { item in
            let topLevelName = ConflictResolver(existingNames: reservedNames)
                .availableName(for: item.lastPathComponent)
            reservedNames.insert(topLevelName)
            return PlannedTopLevelItem(url: item, topLevelName: topLevelName)
        }
    }

    private func enumerateFiles(_ url: URL) throws -> [URL] {
        let isDirectory = try isDirectory(url)

        if !isDirectory {
            return [url]
        }

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: directoryEnumerationOptions
        )

        let files = try enumerator?.compactMap { item -> URL? in
            guard let fileURL = item as? URL else {
                return nil
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? fileURL : nil
        } ?? []

        return files.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private var directoryEnumerationOptions: FileManager.DirectoryEnumerationOptions {
        includesHiddenFiles ? [] : [.skipsHiddenFiles]
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FerryError.pathMissing(url.path)
        }

        return isDirectory.boolValue
    }

    private func relativePath(for file: URL, base: URL) throws -> String {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory)

        guard isDirectory.boolValue else {
            return file.lastPathComponent
        }

        let basePath = base.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else {
            throw FerryError.pathOutsideAuthorizedRoots(filePath)
        }

        return String(filePath.dropFirst(basePath.count + 1))
    }

    private func destinationRelativePath(
        relativePath: String,
        topLevelName: String,
        itemIsDirectory: Bool,
        includeTopLevelName: Bool
    ) -> String {
        guard includeTopLevelName else {
            return relativePath
        }

        guard itemIsDirectory else {
            return topLevelName
        }

        return "\(topLevelName)/\(relativePath)"
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func stableFileId(relativePath: String, size: Int64) -> String {
        let data = Data("\(relativePath):\(size)".utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
