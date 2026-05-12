# Intra Ferry Design

Date: 2026-05-12

## Summary

Intra Ferry is a macOS native menu bar application for moving files, folders, and clipboard content between two Macs on the same internal network. Both Macs run the same app. Each app instance can send and receive, so the system works as a peer-to-peer pair rather than a client/server product.

The first version focuses on a two-Mac workflow:

- Manual peer configuration by IP address or hostname.
- Menu bar app with a compact drag-and-drop transfer window.
- Sender-side remote path selection.
- Large file and folder transfer with progress, chunking, retry, and basic validation.
- Automatic bidirectional clipboard sync.
- Simple prototype-grade security, with protocol fields reserved for later pairing and authentication.

The first version intentionally does not include LAN auto-discovery, strict device pairing, Finder extensions, multi-device management polish, or directory sync semantics.

## Goals

- Let a user drag files or folders from one Mac to a selected path on the other Mac.
- Let a user copy content on one Mac and paste it directly on the other Mac.
- Support large files and folders from the beginning through chunked transfer and resumable tasks.
- Keep the primary UI lightweight and always available from the macOS menu bar.
- Use macOS native APIs for menu bar integration, drag and drop, pasteboard access, file permissions, and background operation.

## Non-Goals

- Full Dropbox-like directory synchronization.
- Finder context menu extension in the first version.
- Automatic LAN discovery in the first version.
- Strong security, pairing, or encryption in the prototype.
- Perfect replication of every private macOS pasteboard type.
- Cross-platform support in the first version.

## Architecture

The project is a Swift/SwiftUI macOS app. The app lives in the menu bar and embeds a local peer service. Every running instance can act as both sender and receiver.

Core modules:

- `MenuBarApp`: Owns the menu bar extra, transfer window, settings, status indicators, and task list UI.
- `PeerService`: Stores peer configuration, checks connectivity, maintains heartbeats, and exposes an interface that can later support Bonjour or LAN discovery.
- `TransferService`: Sends and receives files and folders, manages chunking, validation, progress, cancellation, retry, and task persistence.
- `ClipboardService`: Watches the local pasteboard, serializes supported clipboard content, sends it to peers, receives remote clipboard payloads, and writes them to the local pasteboard.
- `RemoteFileBrowser`: Requests directory listings from the peer and lets the sender choose the target path.

The peer service uses an embedded HTTP server for request/response operations such as directory listing, file chunks, task control, and clipboard writes. WebSocket or long polling can be added for richer status updates, but the first version can derive most progress from the sender-side upload loop.

Protocol payloads include `deviceId`, `protocolVersion`, and reserved authentication fields. These fields are present even in the unauthenticated prototype so later security work does not require a protocol rewrite.

## Peer Configuration

The first version supports one configured peer in the UI while the data model stores peers as a list. This allows a simple two-computer experience now and a straightforward path to multi-device support later.

Peer settings:

- Display name.
- Hostname or IP address.
- Port.
- Optional local device name.

Automatic discovery is not part of the first implementation, but `PeerService` should hide the source of peers behind a small interface so manual peers and discovered peers can share the same connection model later.

## File and Folder Transfer

The sender chooses a target peer and a remote destination path before dropping files. The transfer window accepts both files and folders from Finder.

When files or folders are dropped, `TransferService` creates a transfer task:

- For a file, the task records name, size, modification time, target directory, chunk size, and validation metadata.
- For a folder, the task recursively scans the directory tree and records relative paths, file count, total size, and per-file metadata.
- Large files are split into fixed-size chunks. A practical default is 16 MB, with the value kept configurable internally.
- The receiver writes into a temporary transfer directory first. After all files validate successfully, it moves the completed output into the selected destination.
- If the destination already contains the same file or folder name, the first version automatically creates a copy name, such as `name copy.ext` or `folder copy`.
- Interrupted tasks keep enough state to retry from missing or failed chunks.

The first version validates chunk size and transfer completion. Whole-file hashes should be supported for large files where the additional read cost is acceptable. The implementation should leave the validation strategy explicit so faster or stronger modes can be added later.

The receiver writes only where the running macOS user has permission. For reliability under macOS sandbox and privacy rules, the app should expose a receiving-side "authorized receive locations" setting. Remote browsing and writing are limited to those authorized directories and their children.

## Remote Path Browsing

The sender-side path picker uses `RemoteFileBrowser` to ask the peer for directory listings. It supports:

- Browsing into subdirectories.
- Returning to parent directories within authorized roots.
- Refreshing the current directory.
- Manually entering an absolute path if it falls within an authorized receive location.

The first version does not need a full Finder replacement. It only needs to make common paths such as user directories, project folders, and data directories reachable without opening a terminal.

## Clipboard Sync

Clipboard sync is bidirectional and automatic when enabled.

Each app instance watches `NSPasteboard.general.changeCount`. When the local pasteboard changes, `ClipboardService` reads supported pasteboard items, serializes them into a `ClipboardEnvelope`, and sends the envelope to the configured peer.

The receiver writes the envelope into its local pasteboard. To prevent infinite loops, clipboard writes include source metadata and a local recent-write record. If the watcher observes a change caused by a remote write it just performed, it does not send that content back.

Supported clipboard content is layered:

- Required: plain text, basic rich text, and URLs.
- Required: common image representations such as PNG or TIFF.
- Required best effort: Finder-copied file paths, represented as file-list clipboard data where possible.
- Best effort: other serializable pasteboard types that can be safely read and written.

Private application-specific pasteboard formats are not guaranteed to round-trip. The product promise is that common copy/paste workflows work reliably, not that every app-specific pasteboard flavor is perfectly reproduced.

The menu bar UI includes:

- A clipboard sync enable/pause toggle.
- The source device, timestamp, and content type for the most recent clipboard sync.
- A visible failure state if clipboard serialization or writing fails.

## UI and Workflow

The first version avoids a large main window. The UI is centered on the menu bar and a compact transfer window.

Menu bar menu:

- Peer connection state, including online/offline and last heartbeat.
- Open transfer window.
- Clipboard sync toggle.
- Latest clipboard sync status.
- Transfer task summary.
- Settings.
- Quit.

Transfer window:

- Target peer selector.
- Remote path picker.
- Stable drag-and-drop area for files and folders.
- Transfer task list with file or folder name, total size, speed, progress, status, cancel, and retry actions.

Settings window:

- Local display name.
- Peer host/IP and port.
- Service port.
- Authorized receive locations.
- Temporary transfer directory.
- Clipboard sync default enabled/disabled state.

Typical file workflow:

1. The user opens the transfer window from the menu bar.
2. The user selects the target Mac.
3. The user browses or enters the remote destination path.
4. The user drags files or folders from Finder into the drop area.
5. The task queue starts transferring.
6. On completion, the UI shows the final destination path and offers to copy it.

Typical clipboard workflow:

1. Both apps are running and clipboard sync is enabled.
2. The user copies content on Mac A.
3. Mac B receives the clipboard payload and writes it to its system pasteboard.
4. The user pastes on Mac B through any normal paste action.

## Error Handling

Network, filesystem, and clipboard operations return structured errors. The UI should map each error to a concise explanation and a practical next action.

Important errors:

- Peer offline: suggest checking IP, port, network, and whether the app is running.
- Path missing: allow the user to choose another destination.
- Permission denied: explain that the receive location needs authorization on the target Mac.
- Disk full: show required and available space when available.
- Name conflict: automatically rename and show the final name.
- Network interruption: keep task state and expose retry.
- Clipboard serialization failure: show a menu bar status message without blocking file transfer.
- Clipboard write failure: show a menu bar status message without blocking file transfer.

Partial files are kept in temporary task directories until completion. Failed or canceled tasks should not leave ambiguous half-completed output in the final target directory.

## Security Model

The first version is a trusted-LAN prototype. It does not implement strict authentication or encryption.

The protocol still includes room for:

- Device identity.
- Protocol version.
- Future pairing tokens.
- Future per-request authentication.

The app should make this limitation visible in development documentation. It should not present the prototype as safe for hostile or shared networks.

## Persistence

Local persistence stores:

- Local device configuration.
- Peer list.
- Authorized receive locations.
- Clipboard sync enabled state.
- Active and recent transfer tasks.
- Chunk completion state for resumable transfers.

Sensitive future fields, such as pairing keys, should be stored in Keychain when they are introduced. Prototype configuration can use a local app support directory.

## Testing Strategy

Unit tests:

- `TransferService`: chunk planning, directory scanning, conflict naming, temporary output finalization, retry state.
- `ClipboardService`: pasteboard type serialization, source markers, loop prevention, unsupported type handling.
- `PeerService`: peer configuration, URL construction, heartbeat success and timeout handling.
- `RemoteFileBrowser`: authorized root filtering, path normalization, parent traversal limits.

Integration tests:

- Run two peer service instances on different localhost ports to simulate two Macs.
- Transfer a small file, a large chunked file, and a nested folder.
- Interrupt a transfer and retry it from partial state.
- Sync text clipboard content through the service boundary using test pasteboard abstractions.

Manual acceptance tests on two real Macs:

- Send a small file to a chosen remote path.
- Send a nested folder to a chosen remote path.
- Send a multi-GB file and observe progress.
- Disconnect the network mid-transfer and retry.
- Copy text on one Mac and paste on the other.
- Copy an image on one Mac and paste on the other.
- Pause clipboard sync and verify remote pasteboard is not changed.

## First Implementation Scope

Build one macOS app that can be installed and run on both Macs.

Included:

- Menu bar app shell.
- Manual peer settings.
- Embedded receiving service.
- Heartbeat and connection status.
- Authorized receive locations.
- Remote path browsing within authorized locations.
- Drag-and-drop file and folder transfer.
- Chunked file upload with progress.
- Basic retry after failure.
- Automatic clipboard sync for common content types.
- Clipboard sync pause toggle.
- Basic structured error reporting.

Deferred:

- Bonjour or LAN auto-discovery.
- Strict pairing, authentication, or encryption.
- Finder extension.
- Multi-peer UI polish.
- Full directory synchronization.
- Advanced conflict resolution options.
- Perfect round-trip support for private pasteboard types.
