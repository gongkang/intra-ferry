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
        if types.contains("public.file-url") {
            return .fileURLs
        }
        if types.contains("public.png") || types.contains("public.tiff") {
            return .image
        }
        if types.contains("public.utf8-plain-text") || types.contains("public.rtf") || types.contains("public.url") {
            return .text
        }
        return .unsupported
    }
}
