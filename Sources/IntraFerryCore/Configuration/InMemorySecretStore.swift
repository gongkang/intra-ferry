import Foundation

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokensByKey: [String: AuthToken]

    public init() {
        self.tokensByKey = [:]
    }

    public func save(_ token: AuthToken, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        tokensByKey[key] = token
    }

    public func load(for key: String) throws -> AuthToken? {
        lock.lock()
        defer { lock.unlock() }

        return tokensByKey[key]
    }

    public func delete(for key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        tokensByKey.removeValue(forKey: key)
    }
}
