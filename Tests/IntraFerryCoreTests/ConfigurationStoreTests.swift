import Foundation
import Security
import XCTest
@testable import IntraFerryCore

final class ConfigurationStoreTests: XCTestCase {
    func testSaveAndLoadConfiguration() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let configurationURL = temporaryDirectory.url.appendingPathComponent("configuration.json")
        let stagingURL = temporaryDirectory.url.appendingPathComponent("staging", isDirectory: true)
        let store = FileConfigurationStore(fileURL: configurationURL)

        let configuration = AppConfiguration(
            localDevice: LocalDeviceConfig(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayName: "Daily Mac",
                servicePort: 49491
            ),
            peers: [
                try PeerConfig(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    displayName: "Task Mac",
                    host: "task-mac.local",
                    port: 49492,
                    tokenKey: "peer.task-mac",
                    localDeviceName: "Daily Mac"
                )
            ],
            authorizedRoots: [
                AuthorizedRoot(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    displayName: "Downloads",
                    path: temporaryDirectory.url.appendingPathComponent("Downloads", isDirectory: true).path
                )
            ],
            clipboardSyncEnabled: true,
            stagingDirectoryPath: stagingURL.path
        )

        try store.save(configuration)
        let loadedConfiguration = try store.load()

        XCTAssertEqual(loadedConfiguration, configuration)
    }

    func testInMemorySecretStoreRoundTripsToken() throws {
        let store = InMemorySecretStore()
        let token = AuthToken(rawValue: "prototype-token-123")

        try store.save(token, for: "peer.task-mac")
        let loadedToken = try store.load(for: "peer.task-mac")

        XCTAssertEqual(loadedToken, token)
    }

    func testInMemorySecretStoreReturnsNilForMissingToken() throws {
        let store = InMemorySecretStore()

        let loadedToken = try store.load(for: "missing")

        XCTAssertNil(loadedToken)
    }

    func testInMemorySecretStoreDeleteRemovesToken() throws {
        let store = InMemorySecretStore()

        try store.save(AuthToken(rawValue: "prototype-token-123"), for: "peer.task-mac")
        try store.delete(for: "peer.task-mac")

        XCTAssertNil(try store.load(for: "peer.task-mac"))
    }

    func testKeychainSecretStoreSaveUpdatesExistingTokenWithoutDeleteOrAdd() throws {
        let keychain = RecordingKeychainOperations(updateStatuses: [errSecSuccess])
        let store = KeychainSecretStore(service: "IntraFerryTests", operations: keychain.operations)

        try store.save(AuthToken(rawValue: "replacement-token"), for: "peer.task-mac")

        XCTAssertEqual(keychain.calls, [.update])
    }

    func testKeychainSecretStoreSaveAddsMissingToken() throws {
        let keychain = RecordingKeychainOperations(
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecSuccess]
        )
        let store = KeychainSecretStore(service: "IntraFerryTests", operations: keychain.operations)

        try store.save(AuthToken(rawValue: "new-token"), for: "peer.task-mac")

        XCTAssertEqual(keychain.calls, [.update, .add])
    }

    func testKeychainSecretStoreSaveRetriesUpdateWhenAddFindsDuplicateItem() throws {
        let keychain = RecordingKeychainOperations(
            updateStatuses: [errSecItemNotFound, errSecSuccess],
            addStatuses: [errSecDuplicateItem]
        )
        let store = KeychainSecretStore(service: "IntraFerryTests", operations: keychain.operations)

        try store.save(AuthToken(rawValue: "racing-token"), for: "peer.task-mac")

        XCTAssertEqual(keychain.calls, [.update, .add, .update])
    }

    func testKeychainSecretStoreSaveThrowsPermissionDeniedForUnhandledStatus() throws {
        let keychain = RecordingKeychainOperations(updateStatuses: [errSecAuthFailed])
        let store = KeychainSecretStore(service: "IntraFerryTests", operations: keychain.operations)

        XCTAssertThrowsError(try store.save(AuthToken(rawValue: "token"), for: "peer.task-mac")) { error in
            guard case FerryError.permissionDenied = error else {
                return XCTFail("Expected permissionDenied, got \(error)")
            }
        }
        XCTAssertEqual(keychain.calls, [.update])
    }
}

private final class RecordingKeychainOperations {
    enum Call: Equatable {
        case add
        case update
        case copyMatching
        case delete
    }

    private(set) var calls: [Call] = []
    private var addStatuses: [OSStatus]
    private var updateStatuses: [OSStatus]
    private var copyMatchingStatuses: [OSStatus]
    private var deleteStatuses: [OSStatus]

    init(
        addStatuses: [OSStatus] = [],
        updateStatuses: [OSStatus] = [],
        copyMatchingStatuses: [OSStatus] = [],
        deleteStatuses: [OSStatus] = []
    ) {
        self.addStatuses = addStatuses
        self.updateStatuses = updateStatuses
        self.copyMatchingStatuses = copyMatchingStatuses
        self.deleteStatuses = deleteStatuses
    }

    var operations: KeychainOperations {
        KeychainOperations(
            add: { _ in
                self.calls.append(.add)
                return self.addStatuses.removeFirst()
            },
            update: { _, _ in
                self.calls.append(.update)
                return self.updateStatuses.removeFirst()
            },
            copyMatching: { _, _ in
                self.calls.append(.copyMatching)
                return self.copyMatchingStatuses.removeFirst()
            },
            delete: { _ in
                self.calls.append(.delete)
                return self.deleteStatuses.removeFirst()
            }
        )
    }
}
