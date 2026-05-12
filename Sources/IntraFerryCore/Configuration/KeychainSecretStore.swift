import Foundation
import Security

struct KeychainOperations {
    var add: ([String: Any]) -> OSStatus
    var update: ([String: Any], [String: Any]) -> OSStatus
    var copyMatching: ([String: Any], UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    var delete: ([String: Any]) -> OSStatus

    static func live() -> KeychainOperations {
        KeychainOperations(
            add: { query in
                SecItemAdd(query as CFDictionary, nil)
            },
            update: { query, attributes in
                SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            },
            copyMatching: { query, item in
                SecItemCopyMatching(query as CFDictionary, item)
            },
            delete: { query in
                SecItemDelete(query as CFDictionary)
            }
        )
    }
}

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    private let operations: KeychainOperations

    public init(service: String = "IntraFerry") {
        self.service = service
        self.operations = .live()
    }

    init(service: String = "IntraFerry", operations: KeychainOperations) {
        self.service = service
        self.operations = operations
    }

    public func save(_ token: AuthToken, for key: String) throws {
        let itemQuery = makeItemQuery(for: key)
        let attributesToUpdate = makeValueAttributes(for: token)

        let updateStatus = operations.update(itemQuery, attributesToUpdate)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw permissionDenied(operation: "save", key: key, status: updateStatus)
        }

        let addStatus = operations.add(itemQuery.merging(attributesToUpdate) { _, newValue in newValue })
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = operations.update(itemQuery, attributesToUpdate)
            guard retryStatus == errSecSuccess else {
                throw permissionDenied(operation: "save", key: key, status: retryStatus)
            }
            return
        }

        throw permissionDenied(operation: "save", key: key, status: addStatus)
    }

    public func load(for key: String) throws -> AuthToken? {
        let query = makeItemQuery(for: key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, newValue in newValue }

        var item: CFTypeRef?
        let status = operations.copyMatching(query, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw permissionDenied(operation: "load", key: key, status: status)
        }

        guard
            let data = item as? Data,
            let rawValue = String(data: data, encoding: .utf8)
        else {
            throw FerryError.permissionDenied("Keychain load returned invalid token data for \(key).")
        }

        return AuthToken(rawValue: rawValue)
    }

    public func delete(for key: String) throws {
        let status = operations.delete(makeItemQuery(for: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw permissionDenied(operation: "delete", key: key, status: status)
        }
    }

    private func makeItemQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func makeValueAttributes(for token: AuthToken) -> [String: Any] {
        [
            kSecValueData as String: Data(token.rawValue.utf8)
        ]
    }

    private func permissionDenied(operation: String, key: String, status: OSStatus) -> FerryError {
        FerryError.permissionDenied("Keychain \(operation) failed for \(key) with status \(status).")
    }
}
