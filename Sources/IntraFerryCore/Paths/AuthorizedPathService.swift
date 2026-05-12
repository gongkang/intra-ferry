import Foundation
import Darwin

public struct AuthorizedPathService: Sendable {
    private static let maximumSymbolicLinkDepth = 40

    private let rootPaths: [String]

    public init(roots: [AuthorizedRoot]) {
        self.init(rootPaths: roots.map(\.path))
    }

    public init(rootPaths: [String]) {
        self.rootPaths = rootPaths.compactMap(Self.canonicalPath)
    }

    public func isAuthorized(path: String) -> Bool {
        guard let candidatePath = Self.canonicalPath(path) else {
            return false
        }

        return rootPaths.contains { rootPath in
            candidatePath == rootPath || candidatePath.hasPrefix(Self.pathWithTrailingSeparator(rootPath))
        }
    }

    public func requireAuthorized(path: String) throws {
        guard isAuthorized(path: path) else {
            throw FerryError.pathOutsideAuthorizedRoots(path)
        }
    }

    private static func canonicalPath(_ path: String) -> String? {
        var resolvedComponents: [String] = []
        var pendingComponents = absoluteComponents(for: path)
        var symbolicLinkDepth = 0

        while !pendingComponents.isEmpty {
            let component = pendingComponents.removeFirst()

            if component.isEmpty || component == "." {
                continue
            }

            if component == ".." {
                if !resolvedComponents.isEmpty {
                    resolvedComponents.removeLast()
                }
                continue
            }

            let candidateComponents = resolvedComponents + [component]
            let candidatePath = pathString(from: candidateComponents)
            var status = stat()

            guard lstat(candidatePath, &status) == 0 else {
                guard errno == ENOENT || errno == ENOTDIR else {
                    return nil
                }

                resolvedComponents.append(component)
                continue
            }

            guard (status.st_mode & S_IFMT) == S_IFLNK else {
                resolvedComponents.append(component)
                continue
            }

            symbolicLinkDepth += 1
            guard symbolicLinkDepth <= maximumSymbolicLinkDepth,
                  let destination = symbolicLinkDestination(atPath: candidatePath) else {
                return nil
            }

            let destinationPath = destination as NSString
            let destinationComponents = relativeComponents(for: destination)
            if destinationPath.isAbsolutePath {
                resolvedComponents.removeAll()
            }
            pendingComponents = destinationComponents + pendingComponents
        }

        return pathString(from: resolvedComponents)
    }

    private static func pathWithTrailingSeparator(_ rootPath: String) -> String {
        rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    }

    private static func absoluteComponents(for path: String) -> [String] {
        let absolutePath = URL(fileURLWithPath: path).path
        return relativeComponents(for: absolutePath)
    }

    private static func relativeComponents(for path: String) -> [String] {
        var components = (path as NSString).pathComponents
        if components.first == "/" {
            components.removeFirst()
        }
        return components
    }

    private static func pathString(from components: [String]) -> String {
        guard !components.isEmpty else {
            return "/"
        }

        return "/" + components.joined(separator: "/")
    }

    private static func symbolicLinkDestination(atPath path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))

        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                readlink(path, pointer.baseAddress, pointer.count - 1)
            }

            guard count >= 0 else {
                return nil
            }

            guard count == buffer.count - 1 else {
                return String(decoding: buffer.prefix(count).map(UInt8.init(bitPattern:)), as: UTF8.self)
            }

            buffer = [CChar](repeating: 0, count: buffer.count * 2)
        }
    }
}
