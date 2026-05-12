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
    @Published var connectionStatus = "尚未配置"
    @Published var latestClipboardStatus = "还没有同步剪贴板"
    @Published var transferSummary = "没有正在传输的任务"
    @Published var transferProgress = 0.0
    @Published var localName = "日常电脑"
    @Published var peerHost = ""
    @Published var peerPort = 49491
    @Published var peerPortText = "49491"
    @Published var sharedToken = ""
    @Published var authorizedReceivePath = ""
    @Published var remotePath = ""
    @Published var remoteBrowsePath = ""
    @Published var remoteEntries: [RemoteFileEntry] = []
    @Published var remoteBrowserStatus = "刷新后选择对端目录"
    @Published var settingsStatus = "填写后点击保存"
    @Published var settingsStatusIsError = false

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?
    private var clipboardSyncService: ClipboardSyncService?

    init(environment: AppEnvironment) {
        self.environment = environment
        authorizedReceivePath = Self.defaultAuthorizedReceivePath
        remotePath = Self.defaultAuthorizedReceivePath
        remoteBrowsePath = Self.defaultAuthorizedReceivePath
    }

    func loadAndStartServices() {
        do {
            let config = try environment.configurationStore.load()
            apply(config)
            if let peer = config.peers.first,
               let token = try environment.secretStore.load(for: peer.tokenKey) {
                sharedToken = token.rawValue
                try startPeerServices(config: config, peer: peer, token: token)
                settingsStatus = "已加载现有设置"
                settingsStatusIsError = false
            }
        } catch {
            connectionStatus = "尚未配置"
            settingsStatus = "尚未保存设置"
            settingsStatusIsError = false
        }
    }

    func saveSettings() {
        do {
            settingsStatus = "正在保存..."
            settingsStatusIsError = false
            let validated = try validateSettings()
            let local = LocalDeviceConfig(
                id: configuration?.localDevice.id ?? UUID(),
                displayName: validated.localName,
                servicePort: 49491
            )
            let peer = try PeerConfig(
                id: configuration?.peers.first?.id ?? UUID(),
                displayName: "对端",
                host: validated.peerHost,
                port: validated.peerPort,
                tokenKey: "peer.default",
                localDeviceName: validated.localName
            )
            let receivePath = validated.receivePath
            try FileManager.default.createDirectory(atPath: receivePath, withIntermediateDirectories: true)
            localName = validated.localName
            peerHost = validated.peerHost
            peerPort = validated.peerPort
            peerPortText = String(validated.peerPort)
            sharedToken = validated.sharedToken
            authorizedReceivePath = receivePath
            let roots = [
                AuthorizedRoot(id: configuration?.authorizedRoots.first?.id ?? UUID(), displayName: "接收目录", path: receivePath)
            ]
            let staging = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("IntraFerry", isDirectory: true)
                .path
            let config = AppConfiguration(
                localDevice: local,
                peers: [peer],
                authorizedRoots: roots,
                clipboardSyncEnabled: clipboardSyncEnabled,
                stagingDirectoryPath: staging
            )

            try environment.configurationStore.save(config)
            let token = AuthToken(rawValue: validated.sharedToken)
            try environment.secretStore.save(token, for: peer.tokenKey)
            apply(config)
            try startPeerServices(config: config, peer: peer, token: token)
            connectionStatus = "设置已保存"
            settingsStatus = "已保存，服务正在监听端口 \(config.localDevice.servicePort)"
            settingsStatusIsError = false
        } catch {
            connectionStatus = "保存失败：\(userFacingMessage(for: error))"
            settingsStatus = connectionStatus
            settingsStatusIsError = true
        }
    }

    func refreshRemotePath() async {
        guard let peer = configuration?.peers.first else {
            remoteBrowserStatus = "请先保存设置"
            return
        }

        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else {
                remoteBrowserStatus = "请先保存共享口令"
                return
            }
            let path = normalizedRemoteBrowsePath()
            remoteBrowsePath = path
            remoteBrowserStatus = "正在加载..."
            remoteEntries = try await environment.peerClient.listDirectory(peer: peer, token: token, path: path)
            remoteBrowserStatus = remoteEntries.isEmpty ? "当前目录为空" : "已加载 \(remoteEntries.count) 项"
        } catch {
            remoteEntries = []
            remoteBrowserStatus = "浏览失败：\(userFacingMessage(for: error))"
        }
    }

    func enterRemoteDirectory(_ entry: RemoteFileEntry) async {
        guard entry.isDirectory else {
            return
        }

        remoteBrowsePath = entry.path
        await refreshRemotePath()
    }

    func browseRemoteParent() async {
        remoteBrowsePath = parentPath(for: normalizedRemoteBrowsePath())
        await refreshRemotePath()
    }

    func selectRemoteBrowsePath() {
        remotePath = normalizedRemoteBrowsePath()
        transferSummary = "发送目标：\(remotePath)"
    }

    func sendDroppedFiles(_ urls: [URL]) async {
        guard let peer = configuration?.peers.first else {
            return
        }

        do {
            guard let token = try environment.secretStore.load(for: peer.tokenKey) else {
                return
            }
            transferProgress = 0
            transferSummary = "正在发送 \(urls.count) 个项目"
            let coordinator = TransferCoordinator(planner: TransferPlanner(), client: environment.peerClient)
            let result = try await coordinator.send(items: urls, destinationPath: remotePath, peer: peer, token: token)
            transferProgress = 1
            transferSummary = "已发送到 \(result.finalPath)"
        } catch {
            transferSummary = "传输失败：\(userFacingMessage(for: error))"
        }
    }

    private func apply(_ config: AppConfiguration) {
        configuration = config
        clipboardSyncEnabled = config.clipboardSyncEnabled
        localName = config.localDevice.displayName
        peerHost = config.peers.first?.host ?? ""
        peerPort = config.peers.first?.port ?? 49491
        peerPortText = String(peerPort)
        authorizedReceivePath = config.authorizedRoots.first?.path ?? Self.defaultAuthorizedReceivePath
        remotePath = config.authorizedRoots.first?.path ?? Self.defaultAuthorizedReceivePath
        remoteBrowsePath = remotePath
    }

    private func startPeerServices(config: AppConfiguration, peer: PeerConfig, token: AuthToken) throws {
        peerServiceRuntime?.stop()
        clipboardSyncService?.stop()

        let runtime = PeerServiceRuntime(configuration: config, token: token, pasteboard: environment.pasteboard)
        try runtime.start()
        peerServiceRuntime = runtime
        startClipboardSync(peer: peer, token: token, config: config)
        connectionStatus = "正在监听端口 \(config.localDevice.servicePort)"
    }

    private func startClipboardSync(peer: PeerConfig, token: AuthToken, config: AppConfiguration) {
        let clipboard = ClipboardService(
            localDeviceId: config.localDevice.id,
            pasteboard: environment.pasteboard,
            serializer: ClipboardSerializer(localDeviceId: config.localDevice.id)
        )
        let sync = ClipboardSyncService(clipboard: clipboard, peer: peer, token: token, client: environment.peerClient)
        if clipboardSyncEnabled {
            sync.start()
        }
        clipboardSyncService = sync
    }

    private func userFacingMessage(for error: Error) -> String {
        if let error = error as? PeerConfig.ValidationError {
            switch error {
            case .emptyHost:
                return "对端地址不能为空。"
            case let .whitespaceInHost(host):
                return "对端地址 \(host) 不能包含空格。"
            case let .invalidPort(port):
                return "对端端口 \(port) 必须在 1 到 65535 之间。"
            case let .invalidURL(host, port):
                return "对端地址 \(host) 和端口 \(port) 不能组成有效的 HTTP 地址。"
            }
        }

        if let error = error as? FerryError {
            switch error {
            case let .peerOffline(host, port):
                return "对端 \(host):\(port) 离线。"
            case .invalidToken:
                return "共享口令缺失或无效。"
            case let .unsupportedProtocolVersion(version):
                return "不支持协议版本 \(version)。"
            case let .pathOutsideAuthorizedRoots(path):
                return "路径 \(path) 不在允许接收路径内。"
            case let .pathMissing(path):
                return "路径 \(path) 不存在。"
            case let .permissionDenied(path):
                return "没有访问 \(path) 的权限。"
            case let .diskFull(requiredBytes, availableBytes):
                return "磁盘空间不足。需要 \(requiredBytes) 字节，可用 \(availableBytes) 字节。"
            case let .transferIncomplete(id):
                return "传输 \(id.uuidString) 尚未完成。"
            case .clipboardSerializationFailed:
                return "剪贴板内容无法同步。"
            case .clipboardWriteFailed:
                return "写入剪贴板失败。"
            }
        }

        return error.localizedDescription
    }

    private static var defaultAuthorizedReceivePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func normalizedRemoteBrowsePath() -> String {
        let trimmedPath = remoteBrowsePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? remotePath : trimmedPath
    }

    private func parentPath(for path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedPath != "/" else {
            return "/"
        }

        let parent = URL(fileURLWithPath: standardizedPath).deletingLastPathComponent().path
        return parent.isEmpty ? "/" : parent
    }

    private func validateSettings() throws -> ValidatedSettings {
        let trimmedLocalName = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocalName.isEmpty else {
            throw SettingsValidationError.emptyLocalName
        }

        let trimmedPeerHost = peerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPeerHost.isEmpty else {
            throw SettingsValidationError.emptyPeerHost
        }

        let trimmedPeerPort = peerPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPeerPort.isEmpty else {
            throw SettingsValidationError.emptyPeerPort
        }

        guard let parsedPort = Int(trimmedPeerPort), (1...65535).contains(parsedPort) else {
            throw SettingsValidationError.invalidPeerPort
        }

        let trimmedSharedToken = sharedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSharedToken.isEmpty else {
            throw SettingsValidationError.emptySharedToken
        }

        let trimmedReceivePath = authorizedReceivePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReceivePath.isEmpty else {
            throw SettingsValidationError.emptyReceivePath
        }

        return ValidatedSettings(
            localName: trimmedLocalName,
            peerHost: trimmedPeerHost,
            peerPort: parsedPort,
            sharedToken: trimmedSharedToken,
            receivePath: trimmedReceivePath
        )
    }
}

private struct ValidatedSettings {
    var localName: String
    var peerHost: String
    var peerPort: Int
    var sharedToken: String
    var receivePath: String
}

private enum SettingsValidationError: LocalizedError {
    case emptyLocalName
    case emptyPeerHost
    case emptyPeerPort
    case invalidPeerPort
    case emptySharedToken
    case emptyReceivePath

    var errorDescription: String? {
        switch self {
        case .emptyLocalName:
            return "本机名称不能为空。"
        case .emptyPeerHost:
            return "对端地址不能为空。"
        case .emptyPeerPort:
            return "对端端口不能为空。"
        case .invalidPeerPort:
            return "对端端口必须是 1 到 65535 之间的数字。"
        case .emptySharedToken:
            return "共享口令不能为空。"
        case .emptyReceivePath:
            return "允许接收路径不能为空。"
        }
    }
}
