import Foundation
import Darwin
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
    @Published var localAddressSummary = "正在检测..."

    let environment: AppEnvironment
    private var peerServiceRuntime: PeerServiceRuntime?
    private var clipboardSyncService: ClipboardSyncService?

    init(environment: AppEnvironment) {
        self.environment = environment
        authorizedReceivePath = Self.defaultAuthorizedReceivePath
        refreshLocalAddresses()
    }

    func loadAndStartServices() {
        refreshLocalAddresses()
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
        refreshLocalAddresses()
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

    func refreshLocalAddresses() {
        let addresses = Self.localIPv4Addresses()
        localAddressSummary = addresses.isEmpty ? "未检测到可用内网 IPv4 地址" : addresses.joined(separator: ", ")
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
            var path = normalizedRemoteBrowsePath()
            if path.isEmpty {
                remoteBrowserStatus = "正在加载对端接收路径..."
                let roots = try await environment.peerClient.listAuthorizedRoots(peer: peer, token: token)
                guard let root = roots.first else {
                    remoteEntries = []
                    remoteBrowserStatus = "对端没有配置允许接收路径"
                    return
                }
                path = root.path
                remotePath = root.path
            }
            remoteBrowsePath = path
            remoteBrowserStatus = "正在加载..."
            remoteEntries = try await environment.peerClient.listDirectory(peer: peer, token: token, path: path)
            if remotePath.isEmpty {
                remotePath = path
            }
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
        let path = normalizedRemoteBrowsePath()
        guard !path.isEmpty else {
            await refreshRemotePath()
            return
        }

        remoteBrowsePath = parentPath(for: path)
        await refreshRemotePath()
    }

    func selectRemoteBrowsePath() {
        let path = normalizedRemoteBrowsePath()
        guard !path.isEmpty else {
            remoteBrowserStatus = "请先刷新并选择对端路径"
            return
        }

        remotePath = path
        transferSummary = "发送目标：\(remotePath)"
    }

    func sendDroppedFiles(_ urls: [URL]) async {
        guard let peer = configuration?.peers.first else {
            return
        }
        guard !remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transferSummary = "请先选择发送目标"
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
        remotePath = ""
        remoteBrowsePath = ""
        remoteBrowserStatus = "点击刷新加载对端接收路径"
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

    private static func localIPv4Addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var allAddresses: [(interface: String, address: String)] = []
        var privateAddresses: [(interface: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            guard let socketAddress = current.pointee.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_INET else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            guard isUsableInterface(name: name, flags: current.pointee.ifa_flags),
                  let address = ipv4Address(from: socketAddress) else {
                continue
            }

            let entry = (interface: name, address: address)
            allAddresses.append(entry)
            if isPrivateIPv4(address) {
                privateAddresses.append(entry)
            }
        }

        let preferred = privateAddresses.isEmpty ? allAddresses : privateAddresses
        let sorted = preferred.sorted { lhs, rhs in
            interfacePriority(lhs.interface) < interfacePriority(rhs.interface)
        }

        var seen = Set<String>()
        return sorted.compactMap { entry in
            guard !seen.contains(entry.address) else {
                return nil
            }
            seen.insert(entry.address)
            return entry.address
        }
    }

    private static func isUsableInterface(name: String, flags: UInt32) -> Bool {
        let enabled = flags & UInt32(IFF_UP) != 0
        let running = flags & UInt32(IFF_RUNNING) != 0
        let loopback = flags & UInt32(IFF_LOOPBACK) != 0
        let excludedPrefixes = ["lo", "awdl", "llw", "utun", "ipsec", "gif", "stf", "p2p"]
        let excluded = excludedPrefixes.contains { name.hasPrefix($0) }
        return enabled && running && !loopback && !excluded
    }

    private static func ipv4Address(from socketAddress: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            socketAddress,
            socklen_t(socketAddress.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else {
            return nil
        }
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }
        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }
        return parts[0] == 192 && parts[1] == 168
    }

    private static func interfacePriority(_ name: String) -> Int {
        if name == "en0" {
            return 0
        }
        if name.hasPrefix("en") {
            return 1
        }
        return 2
    }

    private func normalizedRemoteBrowsePath() -> String {
        let trimmedPath = remoteBrowsePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? remotePath.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedPath
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
