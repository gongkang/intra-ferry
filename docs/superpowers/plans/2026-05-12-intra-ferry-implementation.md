# Intra Ferry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first macOS native menu bar app for peer-to-peer file, folder, and clipboard transfer between two Macs on a trusted internal network.

**Architecture:** Use a SwiftPM workspace with a testable `IntraFerryCore` library and a thin `IntraFerryApp` macOS executable target. Core services own models, configuration, authorized paths, transfer planning, receiver state, HTTP routing, clipboard serialization, and integration seams; the app target owns SwiftUI/AppKit menu bar UI and delegates work to core services.

**Tech Stack:** Swift 6.1, SwiftPM, SwiftUI, AppKit, Foundation, Network.framework, CryptoKit, Security.framework, XCTest.

---

## Source Spec

Implement the approved design in `docs/superpowers/specs/2026-05-12-intra-ferry-design.md`.

The first implementation includes manual peer settings, shared prototype token, embedded receiving service, authorized receive locations, remote path browsing, drag-and-drop transfer, chunked upload with retry state, automatic clipboard sync for common content, pause toggle, and structured errors.

## File Structure

Create this structure:

```text
Package.swift
README.md
Sources/
  IntraFerryCore/
    IntraFerryCore.swift
    Models/
      PeerModels.swift
      AuthModels.swift
      PathModels.swift
      TransferModels.swift
      ClipboardModels.swift
      FerryError.swift
    Configuration/
      ConfigurationStore.swift
      SecretStore.swift
      KeychainSecretStore.swift
      InMemorySecretStore.swift
    Paths/
      AuthorizedPathService.swift
      RemoteFileBrowser.swift
    Transfer/
      ConflictResolver.swift
      TransferPlanner.swift
      TransferReceiverStore.swift
      FileTransferReceiver.swift
      TransferCoordinator.swift
    Peer/
      PeerRequest.swift
      PeerRouter.swift
      PeerClient.swift
      URLSessionPeerClient.swift
    HTTP/
      HTTPMessage.swift
      HTTPBodyReader.swift
      NetworkHTTPServer.swift
      PeerHTTPHandler.swift
    Clipboard/
      PasteboardClient.swift
      ClipboardSerializer.swift
      ClipboardFileCache.swift
      ClipboardService.swift
      ClipboardSyncService.swift
    Runtime/
      AppEnvironment.swift
      PeerServiceRuntime.swift
  IntraFerryApp/
    main.swift
    IntraFerryApp.swift
    AppDelegate.swift
    AppState.swift
    Resources/
      Info.plist
    Views/
      MenuBarContentView.swift
      SettingsView.swift
      TransferWindowView.swift
      RemotePathPickerView.swift
      TaskRowView.swift
      DropZoneView.swift
scripts/
  package-macos-app.sh
Tests/
  IntraFerryCoreTests/
    TestSupport/
      TemporaryDirectory.swift
      FakePeerClient.swift
      FakePasteboardClient.swift
    PeerModelsTests.swift
    ConfigurationStoreTests.swift
    AuthorizedPathServiceTests.swift
    TransferPlannerTests.swift
    FileTransferReceiverTests.swift
    PeerRouterTests.swift
    HTTPMessageTests.swift
    PeerHTTPHandlerTests.swift
    ClipboardSerializerTests.swift
    ClipboardFileCacheTests.swift
    ClipboardServiceTests.swift
    ClipboardSyncServiceTests.swift
    LocalPeerIntegrationTests.swift
docs/
  manual-testing.md
```

Responsibilities:

- `Models/`: Small value types and error enums shared across services.
- `Configuration/`: JSON-backed settings and Keychain-backed shared token storage.
- `Paths/`: Authorized root enforcement and remote directory listing.
- `Transfer/`: Manifest creation, chunk planning, idempotent chunk writes, finalization, retry, and sender coordination.
- `Peer/`: Authenticated request routing and peer client protocol.
- `HTTP/`: Minimal HTTP parser/serializer, reliable request-body reader, Network.framework server adapter, and route bridge to `PeerRouter`.
- `Clipboard/`: Pasteboard abstraction, serialization, loop prevention, and file clipboard cache.
- `Runtime/`: Dependency assembly and peer service lifecycle.
- `IntraFerryApp/`: macOS menu bar, settings, transfer window, drag/drop, and UI state only.

## Task 1: SwiftPM Scaffold

**Files:**
- Create: `Package.swift`
- Create: `README.md`
- Create: `Sources/IntraFerryCore/IntraFerryCore.swift`
- Create: `Sources/IntraFerryApp/main.swift`
- Create: `Tests/IntraFerryCoreTests/PeerModelsTests.swift`

- [ ] **Step 1: Create the Swift package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "IntraFerry",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IntraFerryCore", targets: ["IntraFerryCore"]),
        .executable(name: "IntraFerryApp", targets: ["IntraFerryApp"])
    ],
    targets: [
        .target(
            name: "IntraFerryCore",
            dependencies: []
        ),
        .executableTarget(
            name: "IntraFerryApp",
            dependencies: ["IntraFerryCore"]
        ),
        .testTarget(
            name: "IntraFerryCoreTests",
            dependencies: ["IntraFerryCore"]
        )
    ]
)
```

- [ ] **Step 2: Create the initial core module marker**

Create `Sources/IntraFerryCore/IntraFerryCore.swift`:

```swift
public enum IntraFerryCore {
    public static let protocolVersion = "1"
}
```

- [ ] **Step 3: Create a minimal app executable**

Create `Sources/IntraFerryApp/main.swift`:

```swift
import IntraFerryCore

print("Intra Ferry protocol \(IntraFerryCore.protocolVersion)")
```

- [ ] **Step 4: Create the first smoke test**

Create `Tests/IntraFerryCoreTests/PeerModelsTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class PeerModelsTests: XCTestCase {
    func testProtocolVersionStartsAtOne() {
        XCTAssertEqual(IntraFerryCore.protocolVersion, "1")
    }
}
```

- [ ] **Step 5: Add the initial README**

Create `README.md`:

````markdown
# Intra Ferry

Intra Ferry is a macOS menu bar app for peer-to-peer file, folder, and clipboard transfer between two Macs on a trusted internal network.

## Development

Run tests:

```bash
swift test
```

Build:

```bash
swift build
```
````

- [ ] **Step 6: Verify the scaffold**

Run:

```bash
swift test
swift run IntraFerryApp
```

Expected:

```text
Test Suite 'All tests' passed
Intra Ferry protocol 1
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift README.md Sources Tests
git commit -m "chore: scaffold Swift package"
```

## Task 2: Core Domain Models

**Files:**
- Create: `Sources/IntraFerryCore/Models/PeerModels.swift`
- Create: `Sources/IntraFerryCore/Models/AuthModels.swift`
- Create: `Sources/IntraFerryCore/Models/PathModels.swift`
- Create: `Sources/IntraFerryCore/Models/TransferModels.swift`
- Create: `Sources/IntraFerryCore/Models/ClipboardModels.swift`
- Create: `Sources/IntraFerryCore/Models/FerryError.swift`
- Modify: `Tests/IntraFerryCoreTests/PeerModelsTests.swift`

- [ ] **Step 1: Replace the smoke test with model tests**

Replace `Tests/IntraFerryCoreTests/PeerModelsTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class PeerModelsTests: XCTestCase {
    func testPeerBaseURLUsesHostAndPort() throws {
        let peer = PeerConfig(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Task Mac",
            host: "task-mac.local",
            port: 49491,
            tokenKey: "peer.task",
            localDeviceName: "Daily Mac"
        )

        XCTAssertEqual(peer.baseURL.absoluteString, "http://task-mac.local:49491")
    }

    func testAuthTokenRedactionDoesNotExposeSecret() {
        let token = AuthToken(rawValue: "secret-token-123")

        XCTAssertEqual(token.redacted, "sec...123")
    }

    func testFerryErrorDescriptionIsHumanReadable() {
        let error = FerryError.peerOffline(host: "task-mac.local", port: 49491)

        XCTAssertEqual(error.errorDescription, "Peer task-mac.local:49491 is offline.")
    }
}
```

- [ ] **Step 2: Run the model tests and verify they fail**

Run:

```bash
swift test --filter PeerModelsTests
```

Expected:

```text
error: cannot find 'PeerConfig' in scope
```

- [ ] **Step 3: Create peer and auth models**

Create `Sources/IntraFerryCore/Models/PeerModels.swift`:

```swift
import Foundation

public struct PeerConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var host: String
    public var port: Int
    public var tokenKey: String
    public var localDeviceName: String

    public init(id: UUID, displayName: String, host: String, port: Int, tokenKey: String, localDeviceName: String) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.tokenKey = tokenKey
        self.localDeviceName = localDeviceName
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

public struct LocalDeviceConfig: Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var servicePort: Int

    public init(id: UUID, displayName: String, servicePort: Int) {
        self.id = id
        self.displayName = displayName
        self.servicePort = servicePort
    }
}
```

Create `Sources/IntraFerryCore/Models/AuthModels.swift`:

```swift
import Foundation

public struct AuthToken: Codable, Equatable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var redacted: String {
        guard rawValue.count > 6 else { return "******" }
        return "\(rawValue.prefix(3))...\(rawValue.suffix(3))"
    }
}

public struct AuthenticatedPeerRequest: Equatable, Sendable {
    public var deviceId: UUID
    public var protocolVersion: String
    public var token: AuthToken

    public init(deviceId: UUID, protocolVersion: String, token: AuthToken) {
        self.deviceId = deviceId
        self.protocolVersion = protocolVersion
        self.token = token
    }
}
```

- [ ] **Step 4: Create path, transfer, clipboard, and error models**

Create `Sources/IntraFerryCore/Models/PathModels.swift`:

```swift
import Foundation

public struct AuthorizedRoot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var path: String

    public init(id: UUID, displayName: String, path: String) {
        self.id = id
        self.displayName = displayName
        self.path = path
    }
}

public struct RemoteFileEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int64?

    public init(name: String, path: String, isDirectory: Bool, size: Int64?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
    }
}
```

Create `Sources/IntraFerryCore/Models/TransferModels.swift`:

```swift
import Foundation

public struct TransferManifest: Codable, Equatable, Sendable {
    public var transferId: UUID
    public var destinationPath: String
    public var rootName: String
    public var files: [TransferFileManifest]
    public var chunkSize: Int

    public init(transferId: UUID, destinationPath: String, rootName: String, files: [TransferFileManifest], chunkSize: Int) {
        self.transferId = transferId
        self.destinationPath = destinationPath
        self.rootName = rootName
        self.files = files
        self.chunkSize = chunkSize
    }
}

public struct TransferFileManifest: Codable, Equatable, Sendable {
    public var fileId: String
    public var relativePath: String
    public var size: Int64
    public var chunkCount: Int

    public init(fileId: String, relativePath: String, size: Int64, chunkCount: Int) {
        self.fileId = fileId
        self.relativePath = relativePath
        self.size = size
        self.chunkCount = chunkCount
    }
}

public struct ChunkDescriptor: Codable, Equatable, Hashable, Sendable {
    public var fileId: String
    public var chunkIndex: Int
    public var offset: Int64
    public var length: Int

    public init(fileId: String, chunkIndex: Int, offset: Int64, length: Int) {
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.offset = offset
        self.length = length
    }
}

public enum TransferTaskStatus: String, Codable, Equatable, Sendable {
    case waiting
    case running
    case failed
    case completed
    case canceled
}
```

Create `Sources/IntraFerryCore/Models/ClipboardModels.swift`:

```swift
import Foundation

public enum ClipboardContentKind: String, Codable, Equatable, Sendable {
    case text
    case image
    case fileURLs
    case unsupported
}

public struct ClipboardEnvelope: Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceDeviceId: UUID
    public var kind: ClipboardContentKind
    public var items: [ClipboardItem]
    public var createdAt: Date

    public init(id: UUID, sourceDeviceId: UUID, kind: ClipboardContentKind, items: [ClipboardItem], createdAt: Date) {
        self.id = id
        self.sourceDeviceId = sourceDeviceId
        self.kind = kind
        self.items = items
        self.createdAt = createdAt
    }
}

public struct ClipboardItem: Codable, Equatable, Sendable {
    public var typeIdentifier: String
    public var data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}
```

Create `Sources/IntraFerryCore/Models/FerryError.swift`:

```swift
import Foundation

public enum FerryError: LocalizedError, Equatable {
    case peerOffline(host: String, port: Int)
    case invalidToken
    case unsupportedProtocolVersion(String)
    case pathOutsideAuthorizedRoots(String)
    case pathMissing(String)
    case permissionDenied(String)
    case diskFull(requiredBytes: Int64, availableBytes: Int64)
    case transferIncomplete(UUID)
    case clipboardSerializationFailed(String)
    case clipboardWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .peerOffline(host, port):
            return "Peer \(host):\(port) is offline."
        case .invalidToken:
            return "The shared prototype token is missing or invalid."
        case let .unsupportedProtocolVersion(version):
            return "Protocol version \(version) is not supported."
        case let .pathOutsideAuthorizedRoots(path):
            return "Path \(path) is outside authorized receive locations."
        case let .pathMissing(path):
            return "Path \(path) does not exist."
        case let .permissionDenied(path):
            return "Permission denied for \(path)."
        case let .diskFull(requiredBytes, availableBytes):
            return "Not enough disk space. Required \(requiredBytes) bytes, available \(availableBytes) bytes."
        case let .transferIncomplete(id):
            return "Transfer \(id.uuidString) is incomplete."
        case let .clipboardSerializationFailed(reason):
            return "Clipboard serialization failed: \(reason)."
        case let .clipboardWriteFailed(reason):
            return "Clipboard write failed: \(reason)."
        }
    }
}
```

- [ ] **Step 5: Verify model tests pass**

Run:

```bash
swift test --filter PeerModelsTests
```

Expected:

```text
Test Suite 'PeerModelsTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Models Tests/IntraFerryCoreTests/PeerModelsTests.swift
git commit -m "feat: add core domain models"
```

## Task 3: Configuration and Secret Storage

**Files:**
- Create: `Sources/IntraFerryCore/Configuration/ConfigurationStore.swift`
- Create: `Sources/IntraFerryCore/Configuration/SecretStore.swift`
- Create: `Sources/IntraFerryCore/Configuration/KeychainSecretStore.swift`
- Create: `Sources/IntraFerryCore/Configuration/InMemorySecretStore.swift`
- Create: `Tests/IntraFerryCoreTests/TestSupport/TemporaryDirectory.swift`
- Create: `Tests/IntraFerryCoreTests/ConfigurationStoreTests.swift`

- [ ] **Step 1: Write configuration persistence tests**

Create `Tests/IntraFerryCoreTests/TestSupport/TemporaryDirectory.swift`:

```swift
import Foundation
import XCTest

final class TemporaryDirectory {
    let url: URL

    init(function: String = #function) throws {
        let name = function.replacingOccurrences(of: "()", with: "")
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntraFerryTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
```

Create `Tests/IntraFerryCoreTests/ConfigurationStoreTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class ConfigurationStoreTests: XCTestCase {
    func testSaveAndLoadConfiguration() throws {
        let temp = try TemporaryDirectory()
        let store = FileConfigurationStore(fileURL: temp.url.appendingPathComponent("config.json"))
        let config = AppConfiguration(
            localDevice: LocalDeviceConfig(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayName: "Daily Mac",
                servicePort: 49491
            ),
            peers: [
                PeerConfig(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    displayName: "Task Mac",
                    host: "task-mac.local",
                    port: 49491,
                    tokenKey: "peer.task",
                    localDeviceName: "Daily Mac"
                )
            ],
            authorizedRoots: [
                AuthorizedRoot(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    displayName: "Inbox",
                    path: "/Users/task/inbox"
                )
            ],
            clipboardSyncEnabled: true,
            stagingDirectoryPath: "/Users/daily/Library/Application Support/IntraFerry"
        )

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testInMemorySecretStoreRoundTripsToken() throws {
        let store = InMemorySecretStore()

        try store.save(AuthToken(rawValue: "abc123456"), for: "peer.task")

        XCTAssertEqual(try store.load(for: "peer.task"), AuthToken(rawValue: "abc123456"))
    }
}
```

- [ ] **Step 2: Run configuration tests and verify they fail**

Run:

```bash
swift test --filter ConfigurationStoreTests
```

Expected:

```text
error: cannot find 'FileConfigurationStore' in scope
```

- [ ] **Step 3: Implement JSON configuration storage**

Create `Sources/IntraFerryCore/Configuration/ConfigurationStore.swift`:

```swift
import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var localDevice: LocalDeviceConfig
    public var peers: [PeerConfig]
    public var authorizedRoots: [AuthorizedRoot]
    public var clipboardSyncEnabled: Bool
    public var stagingDirectoryPath: String

    public init(
        localDevice: LocalDeviceConfig,
        peers: [PeerConfig],
        authorizedRoots: [AuthorizedRoot],
        clipboardSyncEnabled: Bool,
        stagingDirectoryPath: String
    ) {
        self.localDevice = localDevice
        self.peers = peers
        self.authorizedRoots = authorizedRoots
        self.clipboardSyncEnabled = clipboardSyncEnabled
        self.stagingDirectoryPath = stagingDirectoryPath
    }
}

public protocol ConfigurationStore: Sendable {
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

public final class FileConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> AppConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
    }
}
```

- [ ] **Step 4: Implement secret stores**

Create `Sources/IntraFerryCore/Configuration/SecretStore.swift`:

```swift
import Foundation

public protocol SecretStore: Sendable {
    func save(_ token: AuthToken, for key: String) throws
    func load(for key: String) throws -> AuthToken?
    func delete(for key: String) throws
}
```

Create `Sources/IntraFerryCore/Configuration/InMemorySecretStore.swift`:

```swift
import Foundation

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: AuthToken] = [:]

    public init() {}

    public func save(_ token: AuthToken, for key: String) throws {
        values[key] = token
    }

    public func load(for key: String) throws -> AuthToken? {
        values[key]
    }

    public func delete(for key: String) throws {
        values.removeValue(forKey: key)
    }
}
```

Create `Sources/IntraFerryCore/Configuration/KeychainSecretStore.swift`:

```swift
import Foundation
import Security

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "IntraFerry") {
        self.service = service
    }

    public func save(_ token: AuthToken, for key: String) throws {
        let data = Data(token.rawValue.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw FerryError.permissionDenied("Keychain save failed with status \(status)")
        }
    }

    public func load(for key: String) throws -> AuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw FerryError.permissionDenied("Keychain load failed with status \(status)")
        }
        return AuthToken(rawValue: value)
    }

    public func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 5: Verify configuration tests pass**

Run:

```bash
swift test --filter ConfigurationStoreTests
```

Expected:

```text
Test Suite 'ConfigurationStoreTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Configuration Tests/IntraFerryCoreTests/TestSupport Tests/IntraFerryCoreTests/ConfigurationStoreTests.swift
git commit -m "feat: persist configuration and secrets"
```

## Task 4: Authorized Paths and Remote Browsing

**Files:**
- Create: `Sources/IntraFerryCore/Paths/AuthorizedPathService.swift`
- Create: `Sources/IntraFerryCore/Paths/RemoteFileBrowser.swift`
- Create: `Tests/IntraFerryCoreTests/AuthorizedPathServiceTests.swift`

- [ ] **Step 1: Write authorized path tests**

Create `Tests/IntraFerryCoreTests/AuthorizedPathServiceTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class AuthorizedPathServiceTests: XCTestCase {
    func testAllowsChildInsideAuthorizedRoot() throws {
        let temp = try TemporaryDirectory()
        let inbox = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let service = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: inbox.path)
        ])

        let child = inbox.appendingPathComponent("project").path

        XCTAssertTrue(service.isAuthorized(path: child))
    }

    func testRejectsSiblingWithSimilarPrefix() throws {
        let temp = try TemporaryDirectory()
        let inbox = temp.url.appendingPathComponent("Inbox")
        let sibling = temp.url.appendingPathComponent("InboxOther")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let service = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: inbox.path)
        ])

        XCTAssertFalse(service.isAuthorized(path: sibling.path))
    }

    func testListsOnlyExistingDirectoryChildren() throws {
        let temp = try TemporaryDirectory()
        let inbox = temp.url.appendingPathComponent("Inbox")
        let file = inbox.appendingPathComponent("notes.txt")
        let folder = inbox.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hello".data(using: .utf8)!.write(to: file)
        let service = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: inbox.path)
        ])
        let browser = LocalRemoteFileBrowser(pathService: service)

        let entries = try browser.listDirectory(path: inbox.path)

        XCTAssertEqual(entries.map(\.name).sorted(), ["data", "notes.txt"])
    }
}
```

- [ ] **Step 2: Run authorized path tests and verify they fail**

Run:

```bash
swift test --filter AuthorizedPathServiceTests
```

Expected:

```text
error: cannot find 'AuthorizedPathService' in scope
```

- [ ] **Step 3: Implement authorized path checks**

Create `Sources/IntraFerryCore/Paths/AuthorizedPathService.swift`:

```swift
import Foundation

public struct AuthorizedPathService: Sendable {
    public var roots: [AuthorizedRoot]

    public init(roots: [AuthorizedRoot]) {
        self.roots = roots
    }

    public func isAuthorized(path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in
            let rootPath = URL(fileURLWithPath: root.path).standardizedFileURL.path
            return standardized == rootPath || standardized.hasPrefix(rootPath + "/")
        }
    }

    public func requireAuthorized(path: String) throws {
        guard isAuthorized(path: path) else {
            throw FerryError.pathOutsideAuthorizedRoots(path)
        }
    }
}
```

- [ ] **Step 4: Implement local remote file browsing**

Create `Sources/IntraFerryCore/Paths/RemoteFileBrowser.swift`:

```swift
import Foundation

public protocol RemoteFileBrowsing: Sendable {
    func listDirectory(path: String) throws -> [RemoteFileEntry]
}

public struct LocalRemoteFileBrowser: RemoteFileBrowsing {
    private let pathService: AuthorizedPathService
    private let fileManager: FileManager

    public init(pathService: AuthorizedPathService, fileManager: FileManager = .default) {
        self.pathService = pathService
        self.fileManager = fileManager
    }

    public func listDirectory(path: String) throws -> [RemoteFileEntry] {
        try pathService.requireAuthorized(path: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FerryError.pathMissing(path)
        }

        let url = URL(fileURLWithPath: path)
        return try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .map { item in
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return RemoteFileEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: values.isDirectory == true,
                size: values.fileSize.map(Int64.init)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 5: Verify authorized path tests pass**

Run:

```bash
swift test --filter AuthorizedPathServiceTests
```

Expected:

```text
Test Suite 'AuthorizedPathServiceTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Paths Tests/IntraFerryCoreTests/AuthorizedPathServiceTests.swift
git commit -m "feat: enforce authorized receive paths"
```

## Task 5: Transfer Planning and Conflict Naming

**Files:**
- Create: `Sources/IntraFerryCore/Transfer/ConflictResolver.swift`
- Create: `Sources/IntraFerryCore/Transfer/TransferPlanner.swift`
- Create: `Tests/IntraFerryCoreTests/TransferPlannerTests.swift`

- [ ] **Step 1: Write transfer planner tests**

Create `Tests/IntraFerryCoreTests/TransferPlannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run transfer planner tests and verify they fail**

Run:

```bash
swift test --filter TransferPlannerTests
```

Expected:

```text
error: cannot find 'TransferPlanner' in scope
```

- [ ] **Step 3: Implement conflict naming**

Create `Sources/IntraFerryCore/Transfer/ConflictResolver.swift`:

```swift
import Foundation

public struct ConflictResolver: Sendable {
    private let existingNames: Set<String>

    public init(existingNames: Set<String>) {
        self.existingNames = existingNames
    }

    public func availableName(for proposedName: String) -> String {
        guard existingNames.contains(proposedName) else { return proposedName }
        let url = URL(fileURLWithPath: proposedName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var index = 1
        while true {
            let suffix = index == 1 ? "copy" : "copy \(index)"
            let candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            if !existingNames.contains(candidate) { return candidate }
            index += 1
        }
    }
}
```

- [ ] **Step 4: Implement transfer planning**

Create `Sources/IntraFerryCore/Transfer/TransferPlanner.swift`:

```swift
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

public struct TransferPlanner: Sendable {
    public var chunkSize: Int
    private let fileManager: FileManager

    public init(chunkSize: Int = 16 * 1024 * 1024, fileManager: FileManager = .default) {
        self.chunkSize = chunkSize
        self.fileManager = fileManager
    }

    public func plan(items: [URL], destinationPath: String) throws -> TransferPlan {
        guard let first = items.first else {
            throw FerryError.pathMissing("No transfer items were provided.")
        }

        let rootName = items.count == 1 ? first.lastPathComponent : "Transfer \(UUID().uuidString)"
        var files: [TransferFileManifest] = []
        var sourceFiles: [String: URL] = [:]
        var chunks: [ChunkDescriptor] = []

        for item in items {
            let itemFiles = try enumerateFiles(item)
            for file in itemFiles {
                let relativePath = try relativePath(for: file, base: item)
                let size = try fileSize(file)
                let fileId = stableFileId(relativePath: relativePath, size: size)
                let chunkCount = Int((size + Int64(chunkSize) - 1) / Int64(chunkSize))
                files.append(TransferFileManifest(fileId: fileId, relativePath: relativePath, size: size, chunkCount: chunkCount))
                sourceFiles[fileId] = file
                for index in 0..<chunkCount {
                    let offset = Int64(index * chunkSize)
                    let remaining = size - offset
                    chunks.append(ChunkDescriptor(fileId: fileId, chunkIndex: index, offset: offset, length: Int(min(Int64(chunkSize), remaining))))
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

    private func enumerateFiles(_ url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FerryError.pathMissing(url.path)
        }
        if !isDirectory.boolValue { return [url] }
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        return try enumerator?.compactMap { item in
            guard let fileURL = item as? URL else { return nil }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? fileURL : nil
        } ?? []
    }

    private func relativePath(for file: URL, base: URL) throws -> String {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory)
        if !isDirectory.boolValue { return file.lastPathComponent }
        let basePath = base.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        return String(filePath.dropFirst(basePath.count + 1))
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
```

- [ ] **Step 5: Verify transfer planner tests pass**

Run:

```bash
swift test --filter TransferPlannerTests
```

Expected:

```text
Test Suite 'TransferPlannerTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Transfer Tests/IntraFerryCoreTests/TransferPlannerTests.swift
git commit -m "feat: plan chunked file transfers"
```

## Task 6: Receiver-Side Transfer State

**Files:**
- Create: `Sources/IntraFerryCore/Transfer/TransferReceiverStore.swift`
- Create: `Sources/IntraFerryCore/Transfer/FileTransferReceiver.swift`
- Create: `Tests/IntraFerryCoreTests/FileTransferReceiverTests.swift`

- [ ] **Step 1: Write receiver tests**

Create `Tests/IntraFerryCoreTests/FileTransferReceiverTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class FileTransferReceiverTests: XCTestCase {
    func testUploadsChunksAndFinalizesFile() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pathService = AuthorizedPathService(roots: [
            AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
        ])
        let store = TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        let receiver = FileTransferReceiver(pathService: pathService, store: store)
        let transferId = UUID()
        let fileId = "file-1"
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: fileId, relativePath: "hello.txt", size: 10, chunkCount: 2)],
            chunkSize: 5
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: 1, data: Data("World".utf8))
        try receiver.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: 0, data: Data("Hello".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.lastPathComponent, "hello.txt")
        XCTAssertEqual(try String(contentsOf: finalURL), "HelloWorld")
    }

    func testDuplicateChunkIsIdempotent() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "a.txt",
            files: [TransferFileManifest(fileId: "a", relativePath: "a.txt", size: 1, chunkCount: 1)],
            chunkSize: 1
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "a", chunkIndex: 0, data: Data("A".utf8))
        try receiver.writeChunk(transferId: transferId, fileId: "a", chunkIndex: 0, data: Data("A".utf8))

        XCTAssertEqual(try receiver.missingChunks(transferId: transferId), [])
    }

    func testFinalizesNestedFolderUnderRootName() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "Project",
            files: [TransferFileManifest(fileId: "main", relativePath: "Sources/main.swift", size: 4, chunkCount: 1)],
            chunkSize: 4
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "main", chunkIndex: 0, data: Data("code".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.path, root.appendingPathComponent("Project").path)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Project/Sources/main.swift")), "code")
    }

    func testFinalizationRenamesWhenDestinationExists() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: root.appendingPathComponent("hello.txt"))
        let receiver = FileTransferReceiver(
            pathService: AuthorizedPathService(roots: [AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)]),
            store: TransferReceiverStore(baseDirectory: root.appendingPathComponent(".intra-ferry-tmp"))
        )
        let transferId = UUID()
        let manifest = TransferManifest(
            transferId: transferId,
            destinationPath: root.path,
            rootName: "hello.txt",
            files: [TransferFileManifest(fileId: "hello", relativePath: "hello.txt", size: 3, chunkCount: 1)],
            chunkSize: 3
        )

        try receiver.prepare(manifest)
        try receiver.writeChunk(transferId: transferId, fileId: "hello", chunkIndex: 0, data: Data("new".utf8))
        let finalURL = try receiver.finalize(transferId: transferId)

        XCTAssertEqual(finalURL.lastPathComponent, "hello copy.txt")
        XCTAssertEqual(try String(contentsOf: finalURL), "new")
    }
}
```

- [ ] **Step 2: Run receiver tests and verify they fail**

Run:

```bash
swift test --filter FileTransferReceiverTests
```

Expected:

```text
error: cannot find 'FileTransferReceiver' in scope
```

- [ ] **Step 3: Implement receiver state store**

Create `Sources/IntraFerryCore/Transfer/TransferReceiverStore.swift`:

```swift
import Foundation

public struct TransferReceiverState: Codable, Equatable, Sendable {
    public var manifest: TransferManifest
    public var completedChunks: Set<ChunkDescriptor>
}

public final class TransferReceiverStore: @unchecked Sendable {
    public let baseDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func taskDirectory(for transferId: UUID) -> URL {
        baseDirectory.appendingPathComponent(transferId.uuidString, isDirectory: true)
    }

    public func chunksDirectory(for transferId: UUID) -> URL {
        taskDirectory(for: transferId).appendingPathComponent("chunks", isDirectory: true)
    }

    public func loadState(transferId: UUID) throws -> TransferReceiverState {
        let url = taskDirectory(for: transferId).appendingPathComponent("state.json")
        return try decoder.decode(TransferReceiverState.self, from: Data(contentsOf: url))
    }

    public func saveState(_ state: TransferReceiverState) throws {
        let directory = taskDirectory(for: state.manifest.transferId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: directory.appendingPathComponent("state.json"), options: [.atomic])
    }
}
```

- [ ] **Step 4: Implement chunk writing and finalization**

Create `Sources/IntraFerryCore/Transfer/FileTransferReceiver.swift`:

```swift
import Foundation

public final class FileTransferReceiver: @unchecked Sendable {
    private let pathService: AuthorizedPathService
    private let store: TransferReceiverStore
    private let fileManager: FileManager

    public init(pathService: AuthorizedPathService, store: TransferReceiverStore, fileManager: FileManager = .default) {
        self.pathService = pathService
        self.store = store
        self.fileManager = fileManager
    }

    public func prepare(_ manifest: TransferManifest) throws {
        try pathService.requireAuthorized(path: manifest.destinationPath)
        try fileManager.createDirectory(at: store.chunksDirectory(for: manifest.transferId), withIntermediateDirectories: true)
        try store.saveState(TransferReceiverState(manifest: manifest, completedChunks: []))
    }

    public func writeChunk(transferId: UUID, fileId: String, chunkIndex: Int, data: Data) throws {
        var state = try store.loadState(transferId: transferId)
        guard let file = state.manifest.files.first(where: { $0.fileId == fileId }) else {
            throw FerryError.pathMissing("Unknown fileId \(fileId)")
        }
        let descriptor = ChunkDescriptor(fileId: fileId, chunkIndex: chunkIndex, offset: Int64(chunkIndex * state.manifest.chunkSize), length: data.count)
        guard chunkIndex >= 0, chunkIndex < file.chunkCount else {
            throw FerryError.pathMissing("Invalid chunk \(chunkIndex)")
        }
        let chunkURL = chunkURL(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex)
        try fileManager.createDirectory(at: chunkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: chunkURL, options: [.atomic])
        state.completedChunks.insert(descriptor)
        try store.saveState(state)
    }

    public func missingChunks(transferId: UUID) throws -> [ChunkDescriptor] {
        let state = try store.loadState(transferId: transferId)
        let expected = state.manifest.files.flatMap { file in
            (0..<file.chunkCount).map { index in
                ChunkDescriptor(fileId: file.fileId, chunkIndex: index, offset: Int64(index * state.manifest.chunkSize), length: 0)
            }
        }
        return expected.filter { expectedChunk in
            !state.completedChunks.contains { $0.fileId == expectedChunk.fileId && $0.chunkIndex == expectedChunk.chunkIndex }
        }
    }

    public func finalize(transferId: UUID) throws -> URL {
        let state = try store.loadState(transferId: transferId)
        guard try missingChunks(transferId: transferId).isEmpty else {
            throw FerryError.transferIncomplete(transferId)
        }
        let destination = URL(fileURLWithPath: state.manifest.destinationPath)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let existingNames = Set((try? fileManager.contentsOfDirectory(atPath: destination.path)) ?? [])
        let outputName = ConflictResolver(existingNames: existingNames).availableName(for: state.manifest.rootName)
        let outputURL = destination.appendingPathComponent(outputName)

        for file in state.manifest.files {
            let isSingleRootFile = state.manifest.files.count == 1 && file.relativePath == state.manifest.rootName
            let target = isSingleRootFile ? outputURL : outputURL.appendingPathComponent(file.relativePath)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: target.path, contents: nil)
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            for index in 0..<file.chunkCount {
                let data = try Data(contentsOf: chunkURL(transferId: transferId, fileId: file.fileId, chunkIndex: index))
                try handle.write(contentsOf: data)
            }
        }
        return outputURL
    }

    private func chunkURL(transferId: UUID, fileId: String, chunkIndex: Int) -> URL {
        store.chunksDirectory(for: transferId)
            .appendingPathComponent(fileId, isDirectory: true)
            .appendingPathComponent("\(chunkIndex).chunk")
    }
}
```

- [ ] **Step 5: Verify receiver tests pass**

Run:

```bash
swift test --filter FileTransferReceiverTests
```

Expected:

```text
Test Suite 'FileTransferReceiverTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Transfer/TransferReceiverStore.swift Sources/IntraFerryCore/Transfer/FileTransferReceiver.swift Tests/IntraFerryCoreTests/FileTransferReceiverTests.swift
git commit -m "feat: receive resumable transfer chunks"
```

## Task 7: Authenticated Peer Routing

**Files:**
- Create: `Sources/IntraFerryCore/Peer/PeerRequest.swift`
- Create: `Sources/IntraFerryCore/Peer/PeerRouter.swift`
- Create: `Tests/IntraFerryCoreTests/PeerRouterTests.swift`

- [ ] **Step 1: Write peer router security tests**

Create `Tests/IntraFerryCoreTests/PeerRouterTests.swift`:

```swift
import Foundation
import XCTest
@testable import IntraFerryCore

final class PeerRouterTests: XCTestCase {
    func testRejectsInvalidTokenBeforeDirectoryListing() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "correct"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )

        XCTAssertThrowsError(try router.listDirectory(path: root.path, request: PeerRequest(deviceId: UUID(), protocolVersion: "1", token: AuthToken(rawValue: "wrong")))) { error in
            XCTAssertEqual(error as? FerryError, .invalidToken)
        }
    }

    func testListsDirectoryWithValidToken() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: root.appendingPathComponent("ok.txt"))
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "correct"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )

        let entries = try router.listDirectory(path: root.path, request: PeerRequest(deviceId: UUID(), protocolVersion: "1", token: AuthToken(rawValue: "correct")))

        XCTAssertEqual(entries.map(\.name), ["ok.txt"])
    }
}
```

- [ ] **Step 2: Run peer router tests and verify they fail**

Run:

```bash
swift test --filter PeerRouterTests
```

Expected:

```text
error: cannot find 'PeerRouter' in scope
```

- [ ] **Step 3: Implement peer request**

Create `Sources/IntraFerryCore/Peer/PeerRequest.swift`:

```swift
import Foundation

public struct PeerRequest: Codable, Equatable, Sendable {
    public var deviceId: UUID
    public var protocolVersion: String
    public var token: AuthToken

    public init(deviceId: UUID, protocolVersion: String, token: AuthToken) {
        self.deviceId = deviceId
        self.protocolVersion = protocolVersion
        self.token = token
    }
}
```

- [ ] **Step 4: Implement authenticated router**

Create `Sources/IntraFerryCore/Peer/PeerRouter.swift`:

```swift
import Foundation

public final class PeerRouter: @unchecked Sendable {
    private let localDeviceId: UUID
    private let expectedToken: AuthToken
    private let browser: RemoteFileBrowsing
    private let receiver: FileTransferReceiver?

    public init(localDeviceId: UUID, expectedToken: AuthToken, browser: RemoteFileBrowsing, receiver: FileTransferReceiver?) {
        self.localDeviceId = localDeviceId
        self.expectedToken = expectedToken
        self.browser = browser
        self.receiver = receiver
    }

    public func authenticate(_ request: PeerRequest) throws {
        guard request.protocolVersion == IntraFerryCore.protocolVersion else {
            throw FerryError.unsupportedProtocolVersion(request.protocolVersion)
        }
        guard request.token == expectedToken else {
            throw FerryError.invalidToken
        }
    }

    public func listDirectory(path: String, request: PeerRequest) throws -> [RemoteFileEntry] {
        try authenticate(request)
        return try browser.listDirectory(path: path)
    }

    public func prepareTransfer(_ manifest: TransferManifest, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.prepare(manifest)
    }

    public func writeChunk(transferId: UUID, fileId: String, chunkIndex: Int, data: Data, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex, data: data)
    }

    public func finalizeTransfer(transferId: UUID, request: PeerRequest) throws -> URL? {
        try authenticate(request)
        return try receiver?.finalize(transferId: transferId)
    }
}
```

- [ ] **Step 5: Verify peer router tests pass**

Run:

```bash
swift test --filter PeerRouterTests
```

Expected:

```text
Test Suite 'PeerRouterTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Peer Tests/IntraFerryCoreTests/PeerRouterTests.swift
git commit -m "feat: authenticate peer routes"
```

## Task 8: HTTP Message Layer and Reliable Network Server

**Files:**
- Create: `Sources/IntraFerryCore/HTTP/HTTPMessage.swift`
- Create: `Sources/IntraFerryCore/HTTP/HTTPBodyReader.swift`
- Create: `Sources/IntraFerryCore/HTTP/NetworkHTTPServer.swift`
- Create: `Sources/IntraFerryCore/Peer/PeerClient.swift`
- Create: `Sources/IntraFerryCore/Peer/URLSessionPeerClient.swift`
- Create: `Tests/IntraFerryCoreTests/HTTPMessageTests.swift`

- [ ] **Step 1: Write HTTP parser tests**

Create `Tests/IntraFerryCoreTests/HTTPMessageTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class HTTPMessageTests: XCTestCase {
    func testParsesSimpleRequest() throws {
        let raw = Data("GET /health HTTP/1.1\r\nHost: localhost\r\nX-Intra-Ferry-Token: abc\r\n\r\n".utf8)

        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/health")
        XCTAssertEqual(request.headers["X-Intra-Ferry-Token"], "abc")
        XCTAssertEqual(request.body, Data())
    }

    func testSerializesJSONResponse() {
        let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))

        let text = String(decoding: response.serialize(), as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 2\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{}"))
    }

    func testReadsBodyUsingContentLength() throws {
        let raw = Data("PUT /chunk HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloEXTRA".utf8)

        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.body, Data("hello".utf8))
    }
}
```

- [ ] **Step 2: Run HTTP tests and verify they fail**

Run:

```bash
swift test --filter HTTPMessageTests
```

Expected:

```text
error: cannot find 'HTTPRequest' in scope
```

- [ ] **Step 3: Implement HTTP message parsing and serialization**

Create `Sources/IntraFerryCore/HTTP/HTTPMessage.swift`:

```swift
import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let marker = Data("\r\n\r\n".utf8).range(of: Data("\r\n\r\n".utf8)) else {
            throw FerryError.pathMissing("Invalid HTTP request")
        }
        let headData = data[..<marker.lowerBound]
        let headEnd = marker.upperBound
        let bodyData = data[headEnd...]
        let lines = String(decoding: headData, as: UTF8.self).split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            throw FerryError.pathMissing("Missing request line")
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw FerryError.pathMissing("Invalid request line")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2 {
                headers[String(pieces[0])] = pieces[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0
        guard bodyData.count >= contentLength else {
            throw FerryError.pathMissing("HTTP body shorter than Content-Length")
        }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(bodyData.prefix(contentLength)))
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func serialize() -> Data {
        var lines = ["HTTP/1.1 \(statusCode) \(reasonPhrase)"]
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        for key in allHeaders.keys.sorted() {
            lines.append("\(key): \(allHeaders[key]!)")
        }
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    private var reasonPhrase: String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Internal Server Error"
        }
    }
}
```

- [ ] **Step 4: Implement a reliable HTTP body reader**

Create `Sources/IntraFerryCore/HTTP/HTTPBodyReader.swift`:

```swift
import Foundation
import Network

public final class HTTPBodyReader: @unchecked Sendable {
    public init() {}

    public func readRequest(from connection: NWConnection, maximumBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk(from: connection)
            buffer.append(chunk)
            if let expectedLength = expectedRequestLength(buffer), buffer.count >= expectedLength {
                return Data(buffer.prefix(expectedLength))
            }
            if buffer.count > maximumBytes {
                throw FerryError.diskFull(requiredBytes: Int64(buffer.count), availableBytes: Int64(maximumBytes))
            }
        }
    }

    private func expectedRequestLength(_ data: Data) -> Int? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        let headerText = String(decoding: headerData, as: UTF8.self)
        let contentLength = headerText
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        return headerRange.upperBound + contentLength
    }

    private func receiveChunk(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: FerryError.pathMissing("Connection closed before full HTTP request"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}
```

- [ ] **Step 5: Implement peer client protocol and URLSession client**

Create `Sources/IntraFerryCore/Peer/PeerClient.swift`:

```swift
import Foundation

public protocol PeerClient: Sendable {
    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry]
    func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws
    func uploadChunk(peer: PeerConfig, token: AuthToken, transferId: UUID, fileId: String, chunkIndex: Int, data: Data) async throws
    func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String
}
```

Create `Sources/IntraFerryCore/Peer/URLSessionPeerClient.swift`:

```swift
import Foundation

public final class URLSessionPeerClient: PeerClient, @unchecked Sendable {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry] {
        var components = URLComponents(url: peer.baseURL.appendingPathComponent("directories"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        let data = try await data(for: components.url!, peer: peer, token: token, method: "GET", body: nil)
        return try decoder.decode([RemoteFileEntry].self, from: data)
    }

    public func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws {
        let body = try encoder.encode(manifest)
        _ = try await data(for: peer.baseURL.appendingPathComponent("transfers"), peer: peer, token: token, method: "POST", body: body)
    }

    public func uploadChunk(peer: PeerConfig, token: AuthToken, transferId: UUID, fileId: String, chunkIndex: Int, data: Data) async throws {
        let url = peer.baseURL.appendingPathComponent("transfers/\(transferId.uuidString)/files/\(fileId)/chunks/\(chunkIndex)")
        _ = try await self.data(for: url, peer: peer, token: token, method: "PUT", body: data)
    }

    public func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String {
        let data = try await data(for: peer.baseURL.appendingPathComponent("transfers/\(transferId.uuidString)/finalize"), peer: peer, token: token, method: "POST", body: nil)
        return String(decoding: data, as: UTF8.self)
    }

    private func data(for url: URL, peer: PeerConfig, token: AuthToken, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(IntraFerryCore.protocolVersion, forHTTPHeaderField: "X-Intra-Ferry-Protocol")
        request.setValue(peer.localDeviceName, forHTTPHeaderField: "X-Intra-Ferry-Device-Name")
        request.setValue(peer.id.uuidString, forHTTPHeaderField: "X-Intra-Ferry-Device-Id")
        request.setValue(token.rawValue, forHTTPHeaderField: "X-Intra-Ferry-Token")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FerryError.peerOffline(host: peer.host, port: peer.port)
        }
        return data
    }
}
```

- [ ] **Step 6: Add a Network.framework server adapter**

Create `Sources/IntraFerryCore/HTTP/NetworkHTTPServer.swift`:

```swift
import Foundation
import Network

public final class NetworkHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let port: NWEndpoint.Port
    private let handler: Handler
    private let bodyReader = HTTPBodyReader()
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [handler, bodyReader] connection in
            connection.start(queue: .global())
            Task {
                let response: HTTPResponse
                do {
                    let data = try await bodyReader.readRequest(from: connection)
                    response = await handler(try HTTPRequest.parse(data))
                } catch {
                    response = HTTPResponse(statusCode: 400, headers: [:], body: Data(String(describing: error).utf8))
                }
                connection.send(content: response.serialize(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
```

- [ ] **Step 7: Verify HTTP tests and build pass**

Run:

```bash
swift test --filter HTTPMessageTests
swift build
```

Expected:

```text
Test Suite 'HTTPMessageTests' passed
Build complete
```

- [ ] **Step 8: Commit**

```bash
git add Sources/IntraFerryCore/HTTP Sources/IntraFerryCore/Peer/PeerClient.swift Sources/IntraFerryCore/Peer/URLSessionPeerClient.swift Tests/IntraFerryCoreTests/HTTPMessageTests.swift
git commit -m "feat: add peer HTTP transport"
```

## Task 8A: Peer HTTP Route Bridge

**Files:**
- Create: `Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift`
- Create: `Tests/IntraFerryCoreTests/PeerHTTPHandlerTests.swift`

- [ ] **Step 1: Write route bridge tests**

Create `Tests/IntraFerryCoreTests/PeerHTTPHandlerTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class PeerHTTPHandlerTests: XCTestCase {
    func testDirectoryRouteRejectsInvalidToken() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(root.path)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "wrong"
            ],
            body: Data()
        )

        let response = await handler.handle(request)

        XCTAssertEqual(response.statusCode, 401)
    }

    func testDirectoryRouteListsAuthorizedPath() async throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: root.appendingPathComponent("ok.txt"))
        let router = PeerRouter(
            localDeviceId: UUID(),
            expectedToken: AuthToken(rawValue: "secret"),
            browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [
                AuthorizedRoot(id: UUID(), displayName: "Inbox", path: root.path)
            ])),
            receiver: nil
        )
        let handler = PeerHTTPHandler(router: router)
        let encodedPath = root.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let request = HTTPRequest(
            method: "GET",
            path: "/directories?path=\(encodedPath)",
            headers: [
                "X-Intra-Ferry-Protocol": "1",
                "X-Intra-Ferry-Device-Id": UUID().uuidString,
                "X-Intra-Ferry-Token": "secret"
            ],
            body: Data()
        )

        let response = await handler.handle(request)
        let entries = try JSONDecoder().decode([RemoteFileEntry].self, from: response.body)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(entries.map(\.name), ["ok.txt"])
    }
}
```

- [ ] **Step 2: Run route bridge tests and verify they fail**

Run:

```bash
swift test --filter PeerHTTPHandlerTests
```

Expected:

```text
error: cannot find 'PeerHTTPHandler' in scope
```

- [ ] **Step 3: Implement the route bridge**

Create `Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift`:

```swift
import Foundation

public final class PeerHTTPHandler: @unchecked Sendable {
    private let router: PeerRouter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(router: PeerRouter) {
        self.router = router
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let peerRequest = try peerRequest(from: request)
            switch (request.method, pathOnly(request.path)) {
            case ("GET", "/directories"):
                let path = try queryValue("path", in: request.path)
                let entries = try router.listDirectory(path: path, request: peerRequest)
                return try json(entries)
            case ("POST", "/transfers"):
                let manifest = try decoder.decode(TransferManifest.self, from: request.body)
                try router.prepareTransfer(manifest, request: peerRequest)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())
            case ("PUT", let path) where path.contains("/chunks/"):
                let parts = path.split(separator: "/").map(String.init)
                let transferId = UUID(uuidString: parts[1])!
                let fileId = parts[3]
                let chunkIndex = Int(parts[5])!
                try router.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex, data: request.body, request: peerRequest)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data())
            case ("POST", let path) where path.hasSuffix("/finalize"):
                let parts = path.split(separator: "/").map(String.init)
                let transferId = UUID(uuidString: parts[1])!
                let finalURL = try router.finalizeTransfer(transferId: transferId, request: peerRequest)
                return HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/plain"], body: Data((finalURL?.path ?? "").utf8))
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data("Not found".utf8))
            }
        } catch FerryError.invalidToken {
            return HTTPResponse(statusCode: 401, headers: [:], body: Data("Invalid token".utf8))
        } catch {
            return HTTPResponse(statusCode: 400, headers: [:], body: Data(String(describing: error).utf8))
        }
    }

    private func peerRequest(from request: HTTPRequest) throws -> PeerRequest {
        guard let id = request.headers["X-Intra-Ferry-Device-Id"].flatMap(UUID.init(uuidString:)) else {
            throw FerryError.pathMissing("Missing X-Intra-Ferry-Device-Id")
        }
        return PeerRequest(
            deviceId: id,
            protocolVersion: request.headers["X-Intra-Ferry-Protocol"] ?? "",
            token: AuthToken(rawValue: request.headers["X-Intra-Ferry-Token"] ?? "")
        )
    }

    private func json<T: Encodable>(_ value: T) throws -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: try encoder.encode(value))
    }

    private func pathOnly(_ path: String) -> String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }

    private func queryValue(_ name: String, in path: String) throws -> String {
        guard let components = URLComponents(string: "http://localhost\(path)"),
              let value = components.queryItems?.first(where: { $0.name == name })?.value else {
            throw FerryError.pathMissing("Missing query item \(name)")
        }
        return value
    }
}
```

- [ ] **Step 4: Verify route bridge tests pass**

Run:

```bash
swift test --filter PeerHTTPHandlerTests
```

Expected:

```text
Test Suite 'PeerHTTPHandlerTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift Tests/IntraFerryCoreTests/PeerHTTPHandlerTests.swift
git commit -m "feat: bridge peer HTTP routes"
```

## Task 9: Transfer Sender Coordinator

**Files:**
- Create: `Sources/IntraFerryCore/Transfer/TransferCoordinator.swift`
- Create: `Tests/IntraFerryCoreTests/TestSupport/FakePeerClient.swift`
- Create: `Tests/IntraFerryCoreTests/LocalPeerIntegrationTests.swift`

- [ ] **Step 1: Write coordinator integration test**

Create `Tests/IntraFerryCoreTests/TestSupport/FakePeerClient.swift`:

```swift
import Foundation
@testable import IntraFerryCore

final actor FakePeerClient: PeerClient {
    var prepared: TransferManifest?
    var uploadedChunks: [ChunkDescriptor: Data] = [:]
    var finalized: UUID?

    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry] {
        []
    }

    func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws {
        prepared = manifest
    }

    func uploadChunk(peer: PeerConfig, token: AuthToken, transferId: UUID, fileId: String, chunkIndex: Int, data: Data) async throws {
        uploadedChunks[ChunkDescriptor(fileId: fileId, chunkIndex: chunkIndex, offset: 0, length: data.count)] = data
    }

    func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String {
        finalized = transferId
        return "/Users/task/inbox"
    }
}
```

Create `Tests/IntraFerryCoreTests/LocalPeerIntegrationTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class LocalPeerIntegrationTests: XCTestCase {
    func testCoordinatorUploadsPlannedChunksAndFinalizes() async throws {
        let temp = try TemporaryDirectory()
        let file = temp.url.appendingPathComponent("hello.txt")
        try Data("HelloWorld".utf8).write(to: file)
        let client = FakePeerClient()
        let coordinator = TransferCoordinator(planner: TransferPlanner(chunkSize: 5), client: client)
        let peer = PeerConfig(id: UUID(), displayName: "Task", host: "127.0.0.1", port: 49491, tokenKey: "peer.task", localDeviceName: "Daily")
        let token = AuthToken(rawValue: "secret")

        let result = try await coordinator.send(items: [file], destinationPath: "/Users/task/inbox", peer: peer, token: token)

        XCTAssertEqual(result.finalPath, "/Users/task/inbox")
        XCTAssertEqual(await client.uploadedChunks.count, 2)
        XCTAssertEqual(await client.finalized, result.transferId)
    }
}
```

- [ ] **Step 2: Run coordinator test and verify it fails**

Run:

```bash
swift test --filter LocalPeerIntegrationTests
```

Expected:

```text
error: cannot find 'TransferCoordinator' in scope
```

- [ ] **Step 3: Implement transfer coordinator**

Create `Sources/IntraFerryCore/Transfer/TransferCoordinator.swift`:

```swift
import Foundation

public struct TransferResult: Equatable, Sendable {
    public var transferId: UUID
    public var finalPath: String
}

public final class TransferCoordinator: @unchecked Sendable {
    private let planner: TransferPlanner
    private let client: PeerClient

    public init(planner: TransferPlanner, client: PeerClient) {
        self.planner = planner
        self.client = client
    }

    public func send(items: [URL], destinationPath: String, peer: PeerConfig, token: AuthToken) async throws -> TransferResult {
        let plan = try planner.plan(items: items, destinationPath: destinationPath)
        try await client.prepareTransfer(peer: peer, token: token, manifest: plan.manifest)

        for chunk in plan.chunks {
            guard let fileURL = plan.sourceFiles[chunk.fileId] else {
                throw FerryError.pathMissing(chunk.fileId)
            }
            let data = try readChunk(fileURL: fileURL, offset: chunk.offset, length: chunk.length)
            try await client.uploadChunk(peer: peer, token: token, transferId: plan.manifest.transferId, fileId: chunk.fileId, chunkIndex: chunk.chunkIndex, data: data)
        }

        let finalPath = try await client.finalizeTransfer(peer: peer, token: token, transferId: plan.manifest.transferId)
        return TransferResult(transferId: plan.manifest.transferId, finalPath: finalPath)
    }

    private func readChunk(fileURL: URL, offset: Int64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }
}
```

- [ ] **Step 4: Verify coordinator integration test passes**

Run:

```bash
swift test --filter LocalPeerIntegrationTests
```

Expected:

```text
Test Suite 'LocalPeerIntegrationTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryCore/Transfer/TransferCoordinator.swift Tests/IntraFerryCoreTests/TestSupport/FakePeerClient.swift Tests/IntraFerryCoreTests/LocalPeerIntegrationTests.swift
git commit -m "feat: coordinate sender transfers"
```

## Task 10: Clipboard Serialization and Loop Prevention

**Files:**
- Create: `Sources/IntraFerryCore/Clipboard/PasteboardClient.swift`
- Create: `Sources/IntraFerryCore/Clipboard/ClipboardSerializer.swift`
- Create: `Sources/IntraFerryCore/Clipboard/ClipboardService.swift`
- Create: `Tests/IntraFerryCoreTests/TestSupport/FakePasteboardClient.swift`
- Create: `Tests/IntraFerryCoreTests/ClipboardSerializerTests.swift`
- Create: `Tests/IntraFerryCoreTests/ClipboardServiceTests.swift`

- [ ] **Step 1: Write clipboard serializer tests**

Create `Tests/IntraFerryCoreTests/TestSupport/FakePasteboardClient.swift`:

```swift
import Foundation
@testable import IntraFerryCore

final class FakePasteboardClient: PasteboardClient {
    var changeCount: Int = 0
    var items: [ClipboardItem] = []

    func readItems() throws -> [ClipboardItem] {
        items
    }

    func writeItems(_ items: [ClipboardItem]) throws {
        self.items = items
        changeCount += 1
    }
}
```

Create `Tests/IntraFerryCoreTests/ClipboardSerializerTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class ClipboardSerializerTests: XCTestCase {
    func testSerializesTextEnvelope() throws {
        let serializer = ClipboardSerializer(localDeviceId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        let item = ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))

        let envelope = try serializer.envelope(from: [item])

        XCTAssertEqual(envelope.kind, .text)
        XCTAssertEqual(envelope.items, [item])
    }
}
```

Create `Tests/IntraFerryCoreTests/ClipboardServiceTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class ClipboardServiceTests: XCTestCase {
    func testRemoteWriteIsNotEchoedBack() throws {
        let pasteboard = FakePasteboardClient()
        let localDevice = UUID()
        let remoteDevice = UUID()
        let service = ClipboardService(
            localDeviceId: localDevice,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: localDevice)
        )
        let envelope = ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: remoteDevice,
            kind: .text,
            items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))],
            createdAt: Date()
        )

        try service.applyRemoteEnvelope(envelope)

        XCTAssertFalse(service.shouldSendCurrentPasteboard())
    }
}
```

- [ ] **Step 2: Run clipboard tests and verify they fail**

Run:

```bash
swift test --filter Clipboard
```

Expected:

```text
error: cannot find 'PasteboardClient' in scope
```

- [ ] **Step 3: Implement pasteboard abstraction and serializer**

Create `Sources/IntraFerryCore/Clipboard/PasteboardClient.swift`:

```swift
import AppKit
import Foundation

public protocol PasteboardClient: AnyObject, Sendable {
    var changeCount: Int { get }
    func readItems() throws -> [ClipboardItem]
    func writeItems(_ items: [ClipboardItem]) throws
}

public final class NSPasteboardClient: PasteboardClient, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func readItems() throws -> [ClipboardItem] {
        pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                item.data(forType: type).map { ClipboardItem(typeIdentifier: type.rawValue, data: $0) }
            }
        } ?? []
    }

    public func writeItems(_ items: [ClipboardItem]) throws {
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        for item in items {
            pasteboardItem.setData(item.data, forType: NSPasteboard.PasteboardType(item.typeIdentifier))
        }
        guard pasteboard.writeObjects([pasteboardItem]) else {
            throw FerryError.clipboardWriteFailed("NSPasteboard rejected clipboard items")
        }
    }
}
```

Create `Sources/IntraFerryCore/Clipboard/ClipboardSerializer.swift`:

```swift
import Foundation

public struct ClipboardSerializer: Sendable {
    private let localDeviceId: UUID

    public init(localDeviceId: UUID) {
        self.localDeviceId = localDeviceId
    }

    public func envelope(from items: [ClipboardItem]) throws -> ClipboardEnvelope {
        guard !items.isEmpty else {
            throw FerryError.clipboardSerializationFailed("Pasteboard contains no serializable items")
        }
        return ClipboardEnvelope(
            id: UUID(),
            sourceDeviceId: localDeviceId,
            kind: kind(for: items),
            items: items,
            createdAt: Date()
        )
    }

    private func kind(for items: [ClipboardItem]) -> ClipboardContentKind {
        let types = Set(items.map(\.typeIdentifier))
        if types.contains("public.file-url") { return .fileURLs }
        if types.contains("public.png") || types.contains("public.tiff") { return .image }
        if types.contains("public.utf8-plain-text") || types.contains("public.rtf") || types.contains("public.url") { return .text }
        return .unsupported
    }
}
```

- [ ] **Step 4: Implement clipboard loop prevention**

Create `Sources/IntraFerryCore/Clipboard/ClipboardService.swift`:

```swift
import Foundation

public final class ClipboardService: @unchecked Sendable {
    private let localDeviceId: UUID
    private let pasteboard: PasteboardClient
    private let serializer: ClipboardSerializer
    private var lastRemoteEnvelopeId: UUID?
    private var lastAppliedChangeCount: Int?

    public init(localDeviceId: UUID, pasteboard: PasteboardClient, serializer: ClipboardSerializer) {
        self.localDeviceId = localDeviceId
        self.pasteboard = pasteboard
        self.serializer = serializer
    }

    public func captureLocalEnvelope() throws -> ClipboardEnvelope {
        try serializer.envelope(from: pasteboard.readItems())
    }

    public func applyRemoteEnvelope(_ envelope: ClipboardEnvelope) throws {
        guard envelope.sourceDeviceId != localDeviceId else { return }
        try pasteboard.writeItems(envelope.items)
        lastRemoteEnvelopeId = envelope.id
        lastAppliedChangeCount = pasteboard.changeCount
    }

    public func shouldSendCurrentPasteboard() -> Bool {
        pasteboard.changeCount != lastAppliedChangeCount
    }
}
```

- [ ] **Step 5: Verify clipboard tests pass**

Run:

```bash
swift test --filter Clipboard
```

Expected:

```text
Test Suite 'ClipboardSerializerTests' passed
Test Suite 'ClipboardServiceTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryCore/Clipboard Tests/IntraFerryCoreTests/TestSupport/FakePasteboardClient.swift Tests/IntraFerryCoreTests/ClipboardSerializerTests.swift Tests/IntraFerryCoreTests/ClipboardServiceTests.swift
git commit -m "feat: serialize clipboard envelopes"
```

## Task 11: Finder File Clipboard Cache

**Files:**
- Create: `Sources/IntraFerryCore/Clipboard/ClipboardFileCache.swift`
- Create: `Tests/IntraFerryCoreTests/ClipboardFileCacheTests.swift`

- [ ] **Step 1: Write clipboard file cache tests**

Create `Tests/IntraFerryCoreTests/ClipboardFileCacheTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class ClipboardFileCacheTests: XCTestCase {
    func testCachesCopiedFileAndReturnsLocalFileURLItem() throws {
        let temp = try TemporaryDirectory()
        let source = temp.url.appendingPathComponent("source.txt")
        try Data("cached".utf8).write(to: source)
        let cache = ClipboardFileCache(cacheDirectory: temp.url.appendingPathComponent("ClipboardCache"))

        let items = try cache.cacheFilesForPasteboard([source])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].typeIdentifier, "public.file-url")
        let cachedURL = URL(string: String(decoding: items[0].data, as: UTF8.self))!
        XCTAssertEqual(try String(contentsOf: cachedURL), "cached")
    }
}
```

- [ ] **Step 2: Run clipboard cache tests and verify they fail**

Run:

```bash
swift test --filter ClipboardFileCacheTests
```

Expected:

```text
error: cannot find 'ClipboardFileCache' in scope
```

- [ ] **Step 3: Implement clipboard file cache**

Create `Sources/IntraFerryCore/Clipboard/ClipboardFileCache.swift`:

```swift
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
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        let entries = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try fileManager.removeItem(at: entry)
            }
        }
    }
}
```

- [ ] **Step 4: Verify clipboard cache tests pass**

Run:

```bash
swift test --filter ClipboardFileCacheTests
```

Expected:

```text
Test Suite 'ClipboardFileCacheTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryCore/Clipboard/ClipboardFileCache.swift Tests/IntraFerryCoreTests/ClipboardFileCacheTests.swift
git commit -m "feat: cache Finder clipboard files"
```

## Task 11A: Clipboard Peer Sync and HTTP Endpoint

**Files:**
- Create: `Sources/IntraFerryCore/Clipboard/ClipboardSyncService.swift`
- Modify: `Sources/IntraFerryCore/Peer/PeerClient.swift`
- Modify: `Sources/IntraFerryCore/Peer/URLSessionPeerClient.swift`
- Modify: `Sources/IntraFerryCore/Peer/PeerRouter.swift`
- Modify: `Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift`
- Modify: `Tests/IntraFerryCoreTests/TestSupport/FakePeerClient.swift`
- Create: `Tests/IntraFerryCoreTests/ClipboardSyncServiceTests.swift`
- Modify: `Tests/IntraFerryCoreTests/PeerHTTPHandlerTests.swift`

- [ ] **Step 1: Write clipboard sync tests**

Create `Tests/IntraFerryCoreTests/ClipboardSyncServiceTests.swift`:

```swift
import XCTest
@testable import IntraFerryCore

final class ClipboardSyncServiceTests: XCTestCase {
    func testTickSendsLocalClipboardWhenChanged() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.items = [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))]
        pasteboard.changeCount = 1
        let client = FakePeerClient()
        let localDevice = UUID()
        let peer = PeerConfig(id: UUID(), displayName: "Task", host: "127.0.0.1", port: 49491, tokenKey: "peer.task", localDeviceName: "Daily")
        let service = ClipboardSyncService(
            clipboard: ClipboardService(localDeviceId: localDevice, pasteboard: pasteboard, serializer: ClipboardSerializer(localDeviceId: localDevice)),
            peer: peer,
            token: AuthToken(rawValue: "secret"),
            client: client
        )

        try await service.tick()

        XCTAssertEqual(await client.sentClipboard?.kind, .text)
    }
}
```

Append this test to `Tests/IntraFerryCoreTests/PeerHTTPHandlerTests.swift`:

```swift
func testClipboardRouteAppliesEnvelope() async throws {
    let pasteboard = FakePasteboardClient()
    let localDevice = UUID()
    let router = PeerRouter(
        localDeviceId: localDevice,
        expectedToken: AuthToken(rawValue: "secret"),
        browser: LocalRemoteFileBrowser(pathService: AuthorizedPathService(roots: [])),
        receiver: nil,
        clipboard: ClipboardService(localDeviceId: localDevice, pasteboard: pasteboard, serializer: ClipboardSerializer(localDeviceId: localDevice))
    )
    let handler = PeerHTTPHandler(router: router)
    let envelope = ClipboardEnvelope(
        id: UUID(),
        sourceDeviceId: UUID(),
        kind: .text,
        items: [ClipboardItem(typeIdentifier: "public.utf8-plain-text", data: Data("remote".utf8))],
        createdAt: Date()
    )
    let request = HTTPRequest(
        method: "POST",
        path: "/clipboard",
        headers: [
            "X-Intra-Ferry-Protocol": "1",
            "X-Intra-Ferry-Device-Id": UUID().uuidString,
            "X-Intra-Ferry-Token": "secret"
        ],
        body: try JSONEncoder().encode(envelope)
    )

    let response = await handler.handle(request)

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(pasteboard.items, envelope.items)
}
```

- [ ] **Step 2: Run clipboard sync tests and verify they fail**

Run:

```bash
swift test --filter ClipboardSyncServiceTests
swift test --filter PeerHTTPHandlerTests/testClipboardRouteAppliesEnvelope
```

Expected:

```text
error: cannot find 'ClipboardSyncService' in scope
```

- [ ] **Step 3: Extend peer client with clipboard send**

Modify `Sources/IntraFerryCore/Peer/PeerClient.swift`:

```swift
import Foundation

public protocol PeerClient: Sendable {
    func listDirectory(peer: PeerConfig, token: AuthToken, path: String) async throws -> [RemoteFileEntry]
    func prepareTransfer(peer: PeerConfig, token: AuthToken, manifest: TransferManifest) async throws
    func uploadChunk(peer: PeerConfig, token: AuthToken, transferId: UUID, fileId: String, chunkIndex: Int, data: Data) async throws
    func finalizeTransfer(peer: PeerConfig, token: AuthToken, transferId: UUID) async throws -> String
    func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws
}
```

Modify `Sources/IntraFerryCore/Peer/URLSessionPeerClient.swift` by adding:

```swift
public func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws {
    let body = try encoder.encode(envelope)
    _ = try await data(for: peer.baseURL.appendingPathComponent("clipboard"), peer: peer, token: token, method: "POST", body: body)
}
```

Modify `Tests/IntraFerryCoreTests/TestSupport/FakePeerClient.swift` by adding:

```swift
var sentClipboard: ClipboardEnvelope?

func sendClipboard(peer: PeerConfig, token: AuthToken, envelope: ClipboardEnvelope) async throws {
    sentClipboard = envelope
}
```

- [ ] **Step 4: Extend router and HTTP handler with clipboard route**

Modify `Sources/IntraFerryCore/Peer/PeerRouter.swift`:

```swift
public final class PeerRouter: @unchecked Sendable {
    private let localDeviceId: UUID
    private let expectedToken: AuthToken
    private let browser: RemoteFileBrowsing
    private let receiver: FileTransferReceiver?
    private let clipboard: ClipboardService?

    public init(localDeviceId: UUID, expectedToken: AuthToken, browser: RemoteFileBrowsing, receiver: FileTransferReceiver?, clipboard: ClipboardService? = nil) {
        self.localDeviceId = localDeviceId
        self.expectedToken = expectedToken
        self.browser = browser
        self.receiver = receiver
        self.clipboard = clipboard
    }

    public func authenticate(_ request: PeerRequest) throws {
        guard request.protocolVersion == IntraFerryCore.protocolVersion else {
            throw FerryError.unsupportedProtocolVersion(request.protocolVersion)
        }
        guard request.token == expectedToken else {
            throw FerryError.invalidToken
        }
    }

    public func listDirectory(path: String, request: PeerRequest) throws -> [RemoteFileEntry] {
        try authenticate(request)
        return try browser.listDirectory(path: path)
    }

    public func prepareTransfer(_ manifest: TransferManifest, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.prepare(manifest)
    }

    public func writeChunk(transferId: UUID, fileId: String, chunkIndex: Int, data: Data, request: PeerRequest) throws {
        try authenticate(request)
        try receiver?.writeChunk(transferId: transferId, fileId: fileId, chunkIndex: chunkIndex, data: data)
    }

    public func finalizeTransfer(transferId: UUID, request: PeerRequest) throws -> URL? {
        try authenticate(request)
        return try receiver?.finalize(transferId: transferId)
    }

    public func applyClipboard(_ envelope: ClipboardEnvelope, request: PeerRequest) throws {
        try authenticate(request)
        try clipboard?.applyRemoteEnvelope(envelope)
    }
}
```

Modify `Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift` by adding this switch case before `default`:

```swift
case ("POST", "/clipboard"):
    let envelope = try decoder.decode(ClipboardEnvelope.self, from: request.body)
    try router.applyClipboard(envelope, request: peerRequest)
    return HTTPResponse(statusCode: 200, headers: [:], body: Data())
```

- [ ] **Step 5: Implement clipboard sync service**

Create `Sources/IntraFerryCore/Clipboard/ClipboardSyncService.swift`:

```swift
import Foundation

public final class ClipboardSyncService: @unchecked Sendable {
    private let clipboard: ClipboardService
    private let peer: PeerConfig
    private let token: AuthToken
    private let client: PeerClient
    private var timer: Timer?

    public init(clipboard: ClipboardService, peer: PeerConfig, token: AuthToken, client: PeerClient) {
        self.clipboard = clipboard
        self.peer = peer
        self.token = token
        self.client = client
    }

    public func start(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func tick() async throws {
        guard clipboard.shouldSendCurrentPasteboard() else { return }
        let envelope = try clipboard.captureLocalEnvelope()
        guard envelope.kind != .unsupported else { return }
        try await client.sendClipboard(peer: peer, token: token, envelope: envelope)
    }
}
```

- [ ] **Step 6: Verify clipboard sync tests pass**

Run:

```bash
swift test --filter ClipboardSyncServiceTests
swift test --filter PeerHTTPHandlerTests
```

Expected:

```text
Test Suite 'ClipboardSyncServiceTests' passed
Test Suite 'PeerHTTPHandlerTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add Sources/IntraFerryCore/Clipboard/ClipboardSyncService.swift Sources/IntraFerryCore/Peer Sources/IntraFerryCore/HTTP/PeerHTTPHandler.swift Tests/IntraFerryCoreTests
git commit -m "feat: sync clipboard over peer API"
```

## Task 12: App Runtime Assembly

**Files:**
- Create: `Sources/IntraFerryCore/Runtime/AppEnvironment.swift`
- Create: `Sources/IntraFerryCore/Runtime/PeerServiceRuntime.swift`
- Replace: `Sources/IntraFerryApp/main.swift`
- Create: `Sources/IntraFerryApp/IntraFerryApp.swift`
- Create: `Sources/IntraFerryApp/AppDelegate.swift`
- Create: `Sources/IntraFerryApp/AppState.swift`

- [ ] **Step 1: Build the runtime environment type**

Create `Sources/IntraFerryCore/Runtime/AppEnvironment.swift`:

```swift
import Foundation

public struct AppEnvironment: Sendable {
    public var configurationStore: ConfigurationStore
    public var secretStore: SecretStore
    public var peerClient: PeerClient
    public var pasteboard: PasteboardClient

    public init(configurationStore: ConfigurationStore, secretStore: SecretStore, peerClient: PeerClient, pasteboard: PasteboardClient) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.peerClient = peerClient
        self.pasteboard = pasteboard
    }

    public static func production() -> AppEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IntraFerry", isDirectory: true)
        return AppEnvironment(
            configurationStore: FileConfigurationStore(fileURL: support.appendingPathComponent("config.json")),
            secretStore: KeychainSecretStore(),
            peerClient: URLSessionPeerClient(),
            pasteboard: NSPasteboardClient()
        )
    }
}
```

- [ ] **Step 2: Add peer service runtime assembly**

Create `Sources/IntraFerryCore/Runtime/PeerServiceRuntime.swift`:

```swift
import Foundation

public final class PeerServiceRuntime: @unchecked Sendable {
    private let server: NetworkHTTPServer

    public init(configuration: AppConfiguration, token: AuthToken, pasteboard: PasteboardClient) {
        let pathService = AuthorizedPathService(roots: configuration.authorizedRoots)
        let receiveTempRoot = configuration.authorizedRoots.first
            .map { URL(fileURLWithPath: $0.path).appendingPathComponent(".intra-ferry-tmp", isDirectory: true) }
            ?? URL(fileURLWithPath: configuration.stagingDirectoryPath).appendingPathComponent("receive-tasks", isDirectory: true)
        let receiverStore = TransferReceiverStore(
            baseDirectory: receiveTempRoot
        )
        let receiver = FileTransferReceiver(pathService: pathService, store: receiverStore)
        let clipboard = ClipboardService(
            localDeviceId: configuration.localDevice.id,
            pasteboard: pasteboard,
            serializer: ClipboardSerializer(localDeviceId: configuration.localDevice.id)
        )
        let router = PeerRouter(
            localDeviceId: configuration.localDevice.id,
            expectedToken: token,
            browser: LocalRemoteFileBrowser(pathService: pathService),
            receiver: receiver,
            clipboard: clipboard
        )
        let handler = PeerHTTPHandler(router: router)
        self.server = NetworkHTTPServer(port: UInt16(configuration.localDevice.servicePort)) { request in
            await handler.handle(request)
        }
    }

    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }
}
```

- [ ] **Step 3: Replace the command-line main with a SwiftUI app entry**

Replace `Sources/IntraFerryApp/main.swift`:

```swift
import SwiftUI

IntraFerryApplication.main()
```

Create `Sources/IntraFerryApp/IntraFerryApp.swift`:

```swift
import SwiftUI
import IntraFerryCore

struct IntraFerryApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(state: appDelegate.state)
        }
    }
}
```

- [ ] **Step 4: Add menu bar app delegate and app state**

Create `Sources/IntraFerryApp/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import IntraFerryCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(environment: AppEnvironment.production())

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Ferry"
        statusItem = item
    }
}
```

Create `Sources/IntraFerryApp/AppState.swift`:

```swift
import Foundation
import SwiftUI
import IntraFerryCore

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration?
    @Published var clipboardSyncEnabled = true
    @Published var connectionStatus = "Not configured"
    @Published var latestClipboardStatus = "No clipboard sync yet"
    @Published var transferSummary = "No active transfers"

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadAndStartServices() {
        do {
            let config = try environment.configurationStore.load()
            configuration = config
            clipboardSyncEnabled = config.clipboardSyncEnabled
            if let peer = config.peers.first, let token = try environment.secretStore.load(for: peer.tokenKey) {
                let runtime = PeerServiceRuntime(configuration: config, token: token, pasteboard: environment.pasteboard)
                try runtime.start()
                peerServiceRuntime = runtime
                connectionStatus = "Listening on port \(config.localDevice.servicePort)"
            }
        } catch {
            connectionStatus = "Not configured"
        }
    }
}
```

- [ ] **Step 5: Call service startup from the app delegate**

Modify `Sources/IntraFerryApp/AppDelegate.swift`:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    state.loadAndStartServices()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "Ferry"
    statusItem = item
}
```

- [ ] **Step 6: Verify app target builds**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 7: Commit**

```bash
git add Sources/IntraFerryCore/Runtime Sources/IntraFerryApp
git commit -m "feat: assemble macOS app runtime"
```

## Task 13: Menu Bar, Settings, and Transfer Window UI

**Files:**
- Create: `Sources/IntraFerryApp/Views/MenuBarContentView.swift`
- Create: `Sources/IntraFerryApp/Views/SettingsView.swift`
- Create: `Sources/IntraFerryApp/Views/TransferWindowView.swift`
- Create: `Sources/IntraFerryApp/Views/RemotePathPickerView.swift`
- Create: `Sources/IntraFerryApp/Views/TaskRowView.swift`
- Create: `Sources/IntraFerryApp/Views/DropZoneView.swift`
- Modify: `Sources/IntraFerryApp/AppState.swift`
- Modify: `Sources/IntraFerryApp/AppDelegate.swift`

- [ ] **Step 1: Add SwiftUI views**

Create `Sources/IntraFerryApp/Views/MenuBarContentView.swift`:

```swift
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var state: AppState
    var openTransferWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.connectionStatus).font(.headline)
            Toggle("Clipboard Sync", isOn: $state.clipboardSyncEnabled)
            Text(state.latestClipboardStatus).font(.caption)
            Divider()
            Text(state.transferSummary).font(.caption)
            HStack {
                Button("Open Transfer Window", action: openTransferWindow)
                Button("Settings") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
```

Create `Sources/IntraFerryApp/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            TextField("Local name", text: $state.localName)
            TextField("Peer host", text: $state.peerHost)
            TextField("Peer port", value: $state.peerPort, format: .number)
            SecureField("Shared token", text: $state.sharedToken)
            TextField("Authorized receive path", text: $state.authorizedReceivePath)
            Toggle("Enable clipboard sync by default", isOn: $state.clipboardSyncEnabled)
            Button("Save") { state.saveSettings() }
        }
        .padding()
        .frame(width: 460)
    }
}
```

Create `Sources/IntraFerryApp/Views/TransferWindowView.swift`:

```swift
import SwiftUI

struct TransferWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transfer").font(.title2)
            RemotePathPickerView(state: state)
            DropZoneView { urls in
                Task { await state.sendDroppedFiles(urls) }
            }
            TaskRowView(name: state.transferSummary, progress: state.transferProgress)
        }
        .padding()
        .frame(width: 560, height: 420)
    }
}
```

Create `Sources/IntraFerryApp/Views/RemotePathPickerView.swift`:

```swift
import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Remote path", text: $state.remotePath)
                Button("Refresh") { Task { await state.refreshRemotePath() } }
            }
            if state.remoteEntries.isEmpty {
                Text("No remote entries. Configure an authorized receive location on the peer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(state.remoteEntries) { entry in
                    Button(entry.isDirectory ? "\(entry.name)/" : entry.name) {
                        if entry.isDirectory { state.remotePath = entry.path }
                    }
                }
                .frame(height: 120)
            }
        }
    }
}
```

Create `Sources/IntraFerryApp/Views/TaskRowView.swift`:

```swift
import SwiftUI

struct TaskRowView: View {
    var name: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text(name)
            ProgressView(value: progress)
        }
    }
}
```

Create `Sources/IntraFerryApp/Views/DropZoneView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var onDropURLs: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isTargeted ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [8]))
            .overlay(Text("Drop files or folders here"))
            .frame(height: 160)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                Task {
                    let urls = await loadURLs(from: providers)
                    await MainActor.run { onDropURLs(urls) }
                }
                return true
            }
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                          let data = item as? Data,
                          let value = String(data: data, encoding: .utf8) else {
                        return nil
                    }
                    return URL(string: value)
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }
}
```

- [ ] **Step 2: Bind app state to settings, remote browsing, and transfer**

Modify `Sources/IntraFerryApp/AppState.swift`:

```swift
import Foundation
import SwiftUI
import IntraFerryCore

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration?
    @Published var clipboardSyncEnabled = true {
        didSet {
            clipboardSyncEnabled ? clipboardSyncService?.start() : clipboardSyncService?.stop()
        }
    }
    @Published var connectionStatus = "Not configured"
    @Published var latestClipboardStatus = "No clipboard sync yet"
    @Published var transferSummary = "No active transfers"
    @Published var transferProgress = 0.0
    @Published var localName = "Daily Mac"
    @Published var peerHost = ""
    @Published var peerPort = 49491
    @Published var sharedToken = ""
    @Published var authorizedReceivePath = ""
    @Published var remotePath = ""
    @Published var remoteEntries: [RemoteFileEntry] = []

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?
    private var clipboardSyncService: ClipboardSyncService?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func loadAndStartServices() {
        do {
            let config = try environment.configurationStore.load()
            apply(config)
            if let peer = config.peers.first, let token = try environment.secretStore.load(for: peer.tokenKey) {
                let runtime = PeerServiceRuntime(configuration: config, token: token, pasteboard: environment.pasteboard)
                try runtime.start()
                peerServiceRuntime = runtime
                startClipboardSync(peer: peer, token: token, config: config)
                connectionStatus = "Listening on port \(config.localDevice.servicePort)"
            }
        } catch {
            connectionStatus = "Not configured"
        }
    }

    func saveSettings() {
        let local = LocalDeviceConfig(id: configuration?.localDevice.id ?? UUID(), displayName: localName, servicePort: 49491)
        let peer = PeerConfig(id: configuration?.peers.first?.id ?? UUID(), displayName: "Peer", host: peerHost, port: peerPort, tokenKey: "peer.default", localDeviceName: localName)
        let roots = authorizedReceivePath.isEmpty ? [] : [AuthorizedRoot(id: UUID(), displayName: "Receive", path: authorizedReceivePath)]
        let staging = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IntraFerry", isDirectory: true)
            .path
        let config = AppConfiguration(localDevice: local, peers: [peer], authorizedRoots: roots, clipboardSyncEnabled: clipboardSyncEnabled, stagingDirectoryPath: staging)
        do {
            try environment.configurationStore.save(config)
            try environment.secretStore.save(AuthToken(rawValue: sharedToken), for: peer.tokenKey)
            apply(config)
            connectionStatus = "Saved settings"
        } catch {
            connectionStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    func refreshRemotePath() async {
        guard let peer = configuration?.peers.first else { return }
        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else { return }
            remoteEntries = try await environment.peerClient.listDirectory(peer: peer, token: token, path: remotePath)
        } catch {
            transferSummary = "Remote browse failed: \(error.localizedDescription)"
        }
    }

    func sendDroppedFiles(_ urls: [URL]) async {
        guard let peer = configuration?.peers.first else { return }
        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else { return }
            transferSummary = "Sending \(urls.count) item(s)"
            let coordinator = TransferCoordinator(planner: TransferPlanner(), client: environment.peerClient)
            let result = try await coordinator.send(items: urls, destinationPath: remotePath, peer: peer, token: token)
            transferProgress = 1.0
            transferSummary = "Sent to \(result.finalPath)"
        } catch {
            transferSummary = "Transfer failed: \(error.localizedDescription)"
        }
    }

    private func apply(_ config: AppConfiguration) {
        configuration = config
        clipboardSyncEnabled = config.clipboardSyncEnabled
        localName = config.localDevice.displayName
        peerHost = config.peers.first?.host ?? ""
        peerPort = config.peers.first?.port ?? 49491
        authorizedReceivePath = config.authorizedRoots.first?.path ?? ""
        remotePath = config.authorizedRoots.first?.path ?? remotePath
    }

    private func startClipboardSync(peer: PeerConfig, token: AuthToken, config: AppConfiguration) {
        let clipboard = ClipboardService(localDeviceId: config.localDevice.id, pasteboard: environment.pasteboard, serializer: ClipboardSerializer(localDeviceId: config.localDevice.id))
        let sync = ClipboardSyncService(clipboard: clipboard, peer: peer, token: token, client: environment.peerClient)
        if clipboardSyncEnabled { sync.start() }
        clipboardSyncService = sync
    }
}
```

- [ ] **Step 3: Wire the popover and transfer window into the status item**

Modify `Sources/IntraFerryApp/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import IntraFerryCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(environment: AppEnvironment.production())

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var transferWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.loadAndStartServices()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Ferry"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(state: state, openTransferWindow: { [weak self] in
                self?.showTransferWindow()
            })
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    private func showTransferWindow() {
        if let transferWindow {
            transferWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intra Ferry Transfer"
        window.contentViewController = NSHostingController(rootView: TransferWindowView(state: state))
        window.center()
        window.makeKeyAndOrderFront(nil)
        transferWindow = window
    }
}
```

- [ ] **Step 4: Verify UI target builds**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryApp
git commit -m "feat: add menu bar transfer UI"
```

## Task 13A: macOS App Bundle Packaging

**Files:**
- Create: `Sources/IntraFerryApp/Resources/Info.plist`
- Create: `scripts/package-macos-app.sh`
- Modify: `README.md`

- [ ] **Step 1: Create app bundle Info.plist**

Create `Sources/IntraFerryApp/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>IntraFerryApp</string>
  <key>CFBundleIdentifier</key>
  <string>local.intraferry.app</string>
  <key>CFBundleName</key>
  <string>Intra Ferry</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 2: Create packaging script**

Create `scripts/package-macos-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT_DIR/build/IntraFerry.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/$CONFIGURATION/IntraFerryApp" "$MACOS_DIR/IntraFerryApp"
cp "Sources/IntraFerryApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/IntraFerryApp"

echo "$APP_DIR"
```

- [ ] **Step 3: Make the script executable and document packaging**

Run:

```bash
chmod +x scripts/package-macos-app.sh
```

Append to `README.md`:

```markdown
## Packaging

Build a local macOS app bundle:

```bash
scripts/package-macos-app.sh
open build/IntraFerry.app
```
```

- [ ] **Step 4: Verify packaging**

Run:

```bash
scripts/package-macos-app.sh
test -x build/IntraFerry.app/Contents/MacOS/IntraFerryApp
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' build/IntraFerry.app/Contents/Info.plist
```

Expected:

```text
build/IntraFerry.app
true
```

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryApp/Resources/Info.plist scripts/package-macos-app.sh README.md
git commit -m "chore: package macOS menu bar app"
```

## Task 14: Manual Test Document and Full Verification

**Files:**
- Create: `docs/manual-testing.md`
- Modify: `README.md`

- [ ] **Step 1: Add manual test checklist**

Create `docs/manual-testing.md`:

````markdown
# Intra Ferry Manual Testing

## Local Build

```bash
swift test
swift build
scripts/package-macos-app.sh
```

## Two-Mac Acceptance

1. Install or run Intra Ferry on both Macs.
2. Configure each Mac with the other Mac's host, port, and shared token.
3. Add one authorized receive location on each Mac.
4. Verify the peer state changes from offline to online.
5. Send a small file to the selected remote path.
6. Send a nested folder to the selected remote path.
7. Send a multi-GB file and verify progress remains visible.
8. Disconnect network during transfer, reconnect, and retry.
9. Copy text on Mac A and paste it on Mac B.
10. Copy an image on Mac A and paste it on Mac B.
11. Copy a file in Finder on Mac A and paste the cached copy on Mac B.
12. Pause clipboard sync and verify Mac B's pasteboard does not change.
13. Send a request with an invalid token and verify directory listing, chunk upload, and clipboard write are rejected.
````

- [ ] **Step 2: Link manual tests from README**

Append to `README.md`:

```markdown
## Manual Testing

See `docs/manual-testing.md` for the two-Mac acceptance checklist.
```

- [ ] **Step 3: Run full verification**

Run:

```bash
swift test
swift build
scripts/package-macos-app.sh
test -x build/IntraFerry.app/Contents/MacOS/IntraFerryApp
git diff --check
```

Expected:

```text
Test Suite 'All tests' passed
Build complete
build/IntraFerry.app
```

`git diff --check` prints no output and exits with code 0.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/manual-testing.md
git commit -m "docs: add manual testing checklist"
```

## Execution Notes

- Keep the UI thin. When UI needs behavior, add that behavior to `IntraFerryCore` first and test it there.
- Do not expand scope into Bonjour discovery, production encryption, Finder extensions, or directory sync.
- Use one commit per task. Run the task-specific test before each commit.
- Before calling the implementation finished, run `swift test`, `swift build`, and the manual checklist sections possible on one Mac.

## Spec Coverage Checklist

- Manual peer configuration: Tasks 2, 3, 12, 13.
- Shared prototype token: Tasks 2, 3, 7, 8, 8A.
- Authorized receive locations: Tasks 4, 6, 13.
- Remote path browsing: Tasks 4, 7, 8, 8A, 13.
- File and folder transfer: Tasks 5, 6, 9.
- Chunking and retry state: Tasks 5, 6, 9.
- HTTP receive service and route bridge: Tasks 8, 8A, 12.
- Clipboard text/image serialization: Task 10.
- Clipboard peer sync and endpoint: Task 11A.
- Finder file clipboard cache: Task 11.
- Menu bar and transfer window: Tasks 12, 13.
- macOS app bundle packaging: Task 13A.
- Structured errors: Tasks 2, 4, 6, 7, 10.
- Testing and manual acceptance: Tasks 1-14.
