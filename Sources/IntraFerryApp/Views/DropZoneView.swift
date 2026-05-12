import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var onDropURLs: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary,
                style: StrokeStyle(lineWidth: 2, dash: [8])
            )
            .overlay(Text("把文件或文件夹拖到这里"))
            .frame(height: 160)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                loadURLs(from: providers) { urls in
                    onDropURLs(urls)
                }
                return true
            }
    }

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.url(from: item) {
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
