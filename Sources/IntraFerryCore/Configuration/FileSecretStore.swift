import Foundation

public final class FileSecretStore: SecretStore, @unchecked Sendable {
    private struct SecretFile: Codable {
        var tokensByKey: [String: String]
    }

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ token: AuthToken, for key: String) throws {
        try lock.withLock {
            var file = try loadFile()
            file.tokensByKey[key] = token.rawValue
            try saveFile(file)
        }
    }

    public func load(for key: String) throws -> AuthToken? {
        try lock.withLock {
            let file = try loadFile()
            return file.tokensByKey[key].map(AuthToken.init(rawValue:))
        }
    }

    public func delete(for key: String) throws {
        try lock.withLock {
            var file = try loadFile()
            file.tokensByKey.removeValue(forKey: key)
            try saveFile(file)
        }
    }

    private func loadFile() throws -> SecretFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SecretFile(tokensByKey: [:])
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SecretFile.self, from: data)
    }

    private func saveFile(_ file: SecretFile) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
