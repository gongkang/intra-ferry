import Foundation

public enum FerryError: LocalizedError, Equatable {
    case peerOffline(host: String, port: Int)
    case peerRequestFailed(host: String, port: Int, reason: String)
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
        case let .peerRequestFailed(host, port, reason):
            return "Request to peer \(host):\(port) failed: \(reason)"
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
