import Foundation

public struct ConflictResolver: Sendable {
    private let existingNames: Set<String>

    public init(existingNames: Set<String>) {
        self.existingNames = existingNames
    }

    public func availableName(for proposedName: String) -> String {
        guard existingNames.contains(proposedName) else {
            return proposedName
        }

        let url = URL(fileURLWithPath: proposedName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var index = 1
        while true {
            let suffix = index == 1 ? "copy" : "copy \(index)"
            let candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }
}
