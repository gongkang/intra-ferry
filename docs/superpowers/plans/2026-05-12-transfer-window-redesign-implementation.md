# Transfer Window Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Ferry transfer window into a compact Finder-like workspace with read-only peer status, a focused remote path browser, and full-window drag-to-send behavior.

**Architecture:** Keep all network and transfer protocol code unchanged. Add small SwiftUI views around the existing `AppState`, move file drop loading out of the old permanent drop zone, and let `TransferWindowView` own the full-window drop overlay. Add only lightweight presentation state to `AppState` for peer status, remote roots, recent targets, and selected target checks.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit window hosting, UniformTypeIdentifiers, existing `IntraFerryCore` peer and transfer APIs.

---

## File Structure

- Modify `Sources/IntraFerryApp/AppState.swift`: add transfer-window presentation state and helper methods for remote roots, recent targets, selected target checks, and peer online/offline status.
- Modify `Sources/IntraFerryApp/AppDelegate.swift`: pass `openSettings` into the transfer window and increase the default transfer window size.
- Replace `Sources/IntraFerryApp/Views/TransferWindowView.swift`: top-level two-column layout, full-window drop overlay, and window-level `.onDrop`.
- Replace `Sources/IntraFerryApp/Views/RemotePathPickerView.swift`: remote path bar and main directory list.
- Create `Sources/IntraFerryApp/Views/TransferHeaderView.swift`: read-only peer identity, online/offline badge, and settings button.
- Create `Sources/IntraFerryApp/Views/TransferSidebarView.swift`: receive roots, recent targets, and selected target summary.
- Create `Sources/IntraFerryApp/Views/TransferFooterView.swift`: selected target, transfer summary, and progress.
- Create `Sources/IntraFerryApp/Views/TransferDropOverlayView.swift`: full-window drag overlay.
- Create `Sources/IntraFerryApp/Views/FileDropLoader.swift`: reusable `NSItemProvider` to `[URL]` loader.
- Delete `Sources/IntraFerryApp/Views/DropZoneView.swift`: the permanent drop zone is no longer part of the UI.
- Delete `Sources/IntraFerryApp/Views/TaskRowView.swift`: the footer replaces it.

## Task 1: AppState Transfer Presentation

**Files:**
- Modify: `Sources/IntraFerryApp/AppState.swift`

- [ ] **Step 1: Add transfer-window state and computed properties**

Add this enum above `final class AppState`:

```swift
enum RemotePeerReachability: Equatable {
    case notConfigured
    case checking
    case online
    case offline
}
```

Add these published properties next to the existing remote browser properties:

```swift
@Published var remoteRoots: [AuthorizedRoot] = []
@Published var recentRemoteTargets: [String] = []
@Published var remotePeerReachability: RemotePeerReachability = .notConfigured
```

Add these computed properties inside `AppState`:

```swift
var trimmedRemoteSendTarget: String {
    remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
}

var hasRemoteSendTarget: Bool {
    !trimmedRemoteSendTarget.isEmpty
}

var transferPeerTitle: String {
    guard let peer = configuration?.peers.first else {
        return "目标电脑：未配置"
    }

    return "目标电脑：\(peer.displayName) · \(peer.host):\(peer.port)"
}

var transferPeerStatusText: String {
    switch remotePeerReachability {
    case .notConfigured:
        return "未配置"
    case .checking:
        return "检查中"
    case .online:
        return "在线"
    case .offline:
        return "离线"
    }
}
```

- [ ] **Step 2: Add browse/select helpers**

Add these methods near `enterRemoteDirectory(_:)`:

```swift
func browseRemotePath(_ path: String) async {
    remoteBrowsePath = path
    await refreshRemotePath()
}

func selectRemotePath(_ path: String) {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
        remoteBrowserStatus = "请先刷新并选择对端路径"
        return
    }

    remotePath = trimmedPath
    rememberRecentRemoteTarget(trimmedPath)
    transferSummary = "发送目标：\(remotePath)"
}
```

Change `selectRemoteBrowsePath()` to call the helper:

```swift
func selectRemoteBrowsePath() {
    selectRemotePath(normalizedRemoteBrowsePath())
}
```

Add this private helper near `parentPath(for:)`:

```swift
private func rememberRecentRemoteTarget(_ path: String) {
    recentRemoteTargets.removeAll { $0 == path }
    recentRemoteTargets.insert(path, at: 0)
    if recentRemoteTargets.count > 5 {
        recentRemoteTargets = Array(recentRemoteTargets.prefix(5))
    }
}
```

- [ ] **Step 3: Track roots and peer reachability during browsing**

Inside `refreshRemotePath()`, update the no-peer guard:

```swift
guard let peer = configuration?.peers.first else {
    remotePeerReachability = .notConfigured
    remoteBrowserStatus = "请先保存设置"
    return
}
```

At the start of the `do` block, before loading token or paths:

```swift
remotePeerReachability = .checking
```

Inside the existing token-missing guard, set the reachability before returning:

```swift
guard let token = try environment.secretStore.load(for: peer.tokenKey) else {
    remotePeerReachability = .notConfigured
    remoteBrowserStatus = "请先保存共享口令"
    return
}
```

Replace the root-loading block with:

```swift
if remoteRoots.isEmpty {
    remoteRoots = try await environment.peerClient.listAuthorizedRoots(peer: peer, token: token)
}

var path = normalizedRemoteBrowsePath()
if path.isEmpty {
    remoteBrowserStatus = "正在加载对端接收路径..."
    guard let root = remoteRoots.first else {
        remoteEntries = []
        remotePeerReachability = .online
        remoteBrowserStatus = "对端没有配置允许接收路径"
        return
    }
    path = root.path
    remotePath = root.path
    rememberRecentRemoteTarget(root.path)
}
```

After `remoteEntries = try await ...`, set:

```swift
remotePeerReachability = .online
```

In the `catch` block, set:

```swift
remotePeerReachability = isPeerOffline(error) ? .offline : .online
```

Add this private helper near `userFacingMessage(for:)`:

```swift
private func isPeerOffline(_ error: Error) -> Bool {
    guard let ferryError = error as? FerryError else {
        return false
    }
    if case .peerOffline = ferryError {
        return true
    }
    return false
}
```

- [ ] **Step 4: Reset transfer presentation on config apply**

In `apply(_:)`, after resetting `remoteBrowsePath`, add:

```swift
remoteRoots = []
recentRemoteTargets = []
remotePeerReachability = config.peers.isEmpty ? .notConfigured : .checking
```

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryApp/AppState.swift
git commit -m "feat: add transfer window presentation state"
```

## Task 2: Read-Only Header And Settings Entry

**Files:**
- Create: `Sources/IntraFerryApp/Views/TransferHeaderView.swift`
- Modify: `Sources/IntraFerryApp/AppDelegate.swift`
- Modify: `Sources/IntraFerryApp/Views/TransferWindowView.swift`

- [ ] **Step 1: Create the transfer header view**

Create `Sources/IntraFerryApp/Views/TransferHeaderView.swift`:

```swift
import SwiftUI

struct TransferHeaderView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(state.transferPeerTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Label(state.transferPeerStatusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .help("打开设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusIcon: String {
        switch state.remotePeerReachability {
        case .online:
            return "checkmark.circle.fill"
        case .checking:
            return "clock"
        case .offline:
            return "xmark.circle.fill"
        case .notConfigured:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch state.remotePeerReachability {
        case .online:
            return .green
        case .checking:
            return .secondary
        case .offline:
            return .red
        case .notConfigured:
            return .orange
        }
    }
}
```

- [ ] **Step 2: Pass settings action into the transfer window**

Replace the existing `TransferWindowView` declaration with this version so the new settings action compiles immediately:

```swift
import SwiftUI

struct TransferWindowView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransferHeaderView(state: state, openSettings: openSettings)
            RemotePathPickerView(state: state)
            DropZoneView { urls in
                Task {
                    await state.sendDroppedFiles(urls)
                }
            }
            TaskRowView(name: state.transferSummary, progress: state.transferProgress)
        }
        .padding()
        .frame(width: 680, height: 540)
    }
}
```

Then in `AppDelegate.showTransferWindow()`, replace the hosting controller assignment with:

```swift
window.contentViewController = NSHostingController(
    rootView: TransferWindowView(state: state, openSettings: { [weak self] in
        self?.showSettingsWindow()
    })
)
```

- [ ] **Step 3: Confirm the header is wired**

No additional code is needed if Step 2 replaced `TransferWindowView` exactly. Confirm the old top-level `Text("传输")` is gone and `TransferHeaderView(state: state, openSettings: openSettings)` is the first child in the `VStack`.

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryApp/AppDelegate.swift Sources/IntraFerryApp/Views/TransferHeaderView.swift Sources/IntraFerryApp/Views/TransferWindowView.swift
git commit -m "feat: add transfer window peer header"
```

## Task 3: Path Bar And Directory Browser

**Files:**
- Replace: `Sources/IntraFerryApp/Views/RemotePathPickerView.swift`

- [ ] **Step 1: Replace the path picker with a browser-focused view**

Replace `Sources/IntraFerryApp/Views/RemotePathPickerView.swift` with:

```swift
import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            browserContent
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            if state.remotePath.isEmpty && state.remoteBrowsePath.isEmpty {
                await state.refreshRemotePath()
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.browseRemoteParent() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.bordered)
            .help("上一级")

            TextField("远端路径", text: $state.remoteBrowsePath)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await state.refreshRemotePath() }
                }

            Button {
                Task { await state.refreshRemotePath() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("刷新")

            Button("设为目标") {
                state.selectRemoteBrowsePath()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.remoteBrowsePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var browserContent: some View {
        if state.remoteBrowserStatus.hasPrefix("浏览失败") || state.remoteEntries.isEmpty {
            emptyState
        } else {
            directoryList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(state.remoteBrowserStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyStateIcon: String {
        if state.remoteBrowserStatus.hasPrefix("浏览失败") {
            return "exclamationmark.triangle"
        }
        return "folder"
    }

    private var directoryList: some View {
        List(state.remoteEntries) { entry in
            Button {
                if entry.isDirectory {
                    Task { await state.enterRemoteDirectory(entry) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc")
                        .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                    Text(entry.isDirectory ? "\(entry.name)/" : entry.name)
                        .lineLimit(1)
                    Spacer()
                    if entry.path == state.trimmedRemoteSendTarget {
                        Text("目标")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if entry.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.isDirectory)
        }
        .listStyle(.inset)
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 3: Commit**

```bash
git add Sources/IntraFerryApp/Views/RemotePathPickerView.swift
git commit -m "feat: redesign remote path browser"
```

## Task 4: Sidebar And Main Workspace Layout

**Files:**
- Create: `Sources/IntraFerryApp/Views/TransferSidebarView.swift`
- Create: `Sources/IntraFerryApp/Views/TransferFooterView.swift`
- Replace: `Sources/IntraFerryApp/Views/TransferWindowView.swift`

- [ ] **Step 1: Create the sidebar view**

Create `Sources/IntraFerryApp/Views/TransferSidebarView.swift`:

```swift
import SwiftUI

struct TransferSidebarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("接收根")
            if state.remoteRoots.isEmpty {
                Text("刷新后显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.remoteRoots) { root in
                    sidebarButton(title: root.displayName, subtitle: root.path, systemImage: "externaldrive") {
                        Task { await state.browseRemotePath(root.path) }
                    }
                }
            }

            Divider()

            sectionTitle("最近目标")
            if state.recentRemoteTargets.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.recentRemoteTargets, id: \.self) { path in
                    sidebarButton(title: URL(fileURLWithPath: path).lastPathComponent, subtitle: path, systemImage: "clock") {
                        Task { await state.browseRemotePath(path) }
                    }
                }
            }

            Spacer(minLength: 12)

            sectionTitle("当前目标")
            Text(state.hasRemoteSendTarget ? state.trimmedRemoteSendTarget : "未选择")
                .font(.caption)
                .foregroundStyle(state.hasRemoteSendTarget ? .primary : .secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func sidebarButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? subtitle : title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Create the footer**

Create `Sources/IntraFerryApp/Views/TransferFooterView.swift`:

```swift
import SwiftUI

struct TransferFooterView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(state.hasRemoteSendTarget ? "发送目标：\(state.trimmedRemoteSendTarget)" : "发送目标：未选择")
                    .font(.caption)
                    .foregroundStyle(state.hasRemoteSendTarget ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(state.transferSummary)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: state.transferProgress)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progressText: String {
        "\(Int((state.transferProgress * 100).rounded()))%"
    }
}
```

- [ ] **Step 3: Replace the transfer window structure**

Replace `Sources/IntraFerryApp/Views/TransferWindowView.swift` with:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct TransferWindowView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TransferHeaderView(state: state, openSettings: openSettings)
            Divider()
            HStack(spacing: 0) {
                TransferSidebarView(state: state)
                Divider()
                RemotePathPickerView(state: state)
            }
            TransferFooterView(state: state)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryApp/Views/TransferSidebarView.swift Sources/IntraFerryApp/Views/TransferFooterView.swift Sources/IntraFerryApp/Views/TransferWindowView.swift
git commit -m "feat: add transfer workspace layout"
```

## Task 5: Full-Window Drag Loading And Overlay

**Files:**
- Create: `Sources/IntraFerryApp/Views/FileDropLoader.swift`
- Create: `Sources/IntraFerryApp/Views/TransferDropOverlayView.swift`
- Modify: `Sources/IntraFerryApp/Views/TransferWindowView.swift`
- Delete: `Sources/IntraFerryApp/Views/DropZoneView.swift`

- [ ] **Step 1: Create a reusable file drop loader**

Create `Sources/IntraFerryApp/Views/FileDropLoader.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

enum FileDropLoader {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = url(from: item) {
                    accumulator.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.values)
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return URL(string: value)
        }
        return nil
    }
}

private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ url: URL) {
        lock.lock()
        storedValues.append(url)
        lock.unlock()
    }
}
```

- [ ] **Step 2: Create the full-window overlay**

Create `Sources/IntraFerryApp/Views/TransferDropOverlayView.swift`:

```swift
import SwiftUI

struct TransferDropOverlayView: View {
    var targetPath: String

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.88)
            VStack(spacing: 14) {
                Image(systemName: targetPath.isEmpty ? "exclamationmark.triangle" : "tray.and.arrow.up.fill")
                    .font(.system(size: 48, weight: .semibold))
                Text(targetPath.isEmpty ? "先选择发送目标" : "松开发送")
                    .font(.system(size: 30, weight: .bold))
                Text(targetPath.isEmpty ? "请先在远端目录中点击“设为目标”" : "发送到 \(targetPath)")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(28)
            }
        }
        .transition(.opacity)
    }
}
```

- [ ] **Step 3: Wire the overlay and window-level drop**

Update `TransferWindowView.body` so the existing `VStack` is wrapped in a `ZStack`:

```swift
var body: some View {
    ZStack {
        VStack(spacing: 0) {
            TransferHeaderView(state: state, openSettings: openSettings)
            Divider()
            HStack(spacing: 0) {
                TransferSidebarView(state: state)
                Divider()
                RemotePathPickerView(state: state)
            }
            TransferFooterView(state: state)
        }

        if isDropTargeted {
            TransferDropOverlayView(targetPath: state.trimmedRemoteSendTarget)
        }
    }
    .frame(minWidth: 760, minHeight: 520)
    .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
        guard state.hasRemoteSendTarget else {
            state.transferSummary = "请先选择发送目标"
            return true
        }

        FileDropLoader.loadURLs(from: providers) { urls in
            Task {
                await state.sendDroppedFiles(urls)
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Delete the old permanent drop zone**

Delete `Sources/IntraFerryApp/Views/DropZoneView.swift` with this patch:

```patch
*** Begin Patch
*** Delete File: Sources/IntraFerryApp/Views/DropZoneView.swift
*** End Patch
```

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/IntraFerryApp/Views/FileDropLoader.swift Sources/IntraFerryApp/Views/TransferDropOverlayView.swift Sources/IntraFerryApp/Views/TransferWindowView.swift
git add -u Sources/IntraFerryApp/Views/DropZoneView.swift
git commit -m "feat: use full-window transfer drop target"
```

## Task 6: Footer, Window Size, And Cleanup

**Files:**
- Modify: `Sources/IntraFerryApp/AppDelegate.swift`
- Delete: `Sources/IntraFerryApp/Views/TaskRowView.swift`
- Modify: `README.md`

- [ ] **Step 1: Increase the default transfer window size**

In `AppDelegate.showTransferWindow()`, change the transfer window content rect from:

```swift
contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
```

to:

```swift
contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
```

- [ ] **Step 2: Delete the old task row**

Delete `Sources/IntraFerryApp/Views/TaskRowView.swift` with this patch:

```patch
*** Begin Patch
*** Delete File: Sources/IntraFerryApp/Views/TaskRowView.swift
*** End Patch
```

- [ ] **Step 3: Update README usage wording**

In `README.md`, replace:

```text
5. 把文件或文件夹拖到拖拽区。
```

with:

```text
5. 把文件或文件夹拖进传输窗口，出现“松开发送”后松开鼠标。
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: command exits with code `0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/IntraFerryApp/AppDelegate.swift README.md
git add -u Sources/IntraFerryApp/Views/TaskRowView.swift
git commit -m "feat: polish transfer window footer"
```

## Task 7: Package And Manual Verification

**Files:**
- Modify: `docs/manual-testing.md`

- [ ] **Step 1: Update manual testing checklist**

In `docs/manual-testing.md`, replace the single-machine transfer checks at lines 38-41 with:

```text
7. 打开传输窗口，确认顶部目标电脑为只读文本，右侧显示在线/离线状态和设置按钮。
8. 确认路径栏左侧是上一级按钮，中间是远端路径，右侧是刷新按钮和“设为目标”按钮。
9. 点击 `刷新`，确认对端路径浏览区能加载目录。
10. 进入一个目录，点击 `设为目标`。
11. 从 Finder 拖文件进入传输窗口，确认整个窗口显示“松开发送”覆盖层。
12. 松开鼠标，确认传输完成。
```

Replace the dual-machine transfer checks at lines 54-56 with:

```text
10. 在 A 打开传输窗口，刷新并选择 B 的接收目录。
11. 从 A 拖一个小文件进入传输窗口，确认整个窗口显示“松开发送”，松开后文件出现在 B 的目标目录。
12. 从 A 拖一个嵌套文件夹进入传输窗口，确认 B 侧目录结构完整。
13. 关闭再重新打开传输窗口，不选择发送目标时拖入文件，确认不会开始传输，并显示“请先选择发送目标”。
```

- [ ] **Step 2: Build and package**

Run:

```bash
swift build
scripts/package-macos-app.sh
```

Expected: both commands exit with code `0`, and `build/IntraFerry.app` exists.

- [ ] **Step 3: Restart the app**

Run:

```bash
pkill -f IntraFerryApp || true
open build/IntraFerry.app
```

Expected: Ferry appears in the macOS menu bar.

- [ ] **Step 4: Manual UI verification**

Open the transfer window and verify:

```text
1. 顶部目标电脑不可编辑。
2. 顶部右侧有在线/离线状态和设置按钮。
3. 路径栏左侧是上一级按钮。
4. 路径栏右侧是刷新按钮。
5. 目录列表占据主要空间。
6. 文件项不可作为目标进入，目录项可进入。
7. “设为目标”会更新底部发送目标。
8. 拖文件进入窗口时，全窗口显示“松开发送”。
9. 松开鼠标后传输开始。
```

- [ ] **Step 5: Commit**

```bash
git add docs/manual-testing.md
git commit -m "docs: update transfer window manual checks"
```

## Final Verification

Run:

```bash
git status --short
swift build
scripts/package-macos-app.sh
```

Expected:

```text
git status --short
```

prints no tracked source changes, and both build commands exit with code `0`.
