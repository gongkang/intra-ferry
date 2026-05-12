public protocol SecretStore: Sendable {
    func save(_ token: AuthToken, for key: String) throws
    func load(for key: String) throws -> AuthToken?
    func delete(for key: String) throws
}
