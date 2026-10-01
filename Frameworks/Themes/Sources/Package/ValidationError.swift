public import Foundation

/// A structural package error with an author-facing location and explanation.
public struct ValidationError: Error, Sendable, Equatable, LocalizedError {
    public let path: String
    public let reason: String
    public var errorDescription: String? { "\(path): \(reason)" }

    /// Describes a failed package requirement.
    /// - Parameters:
    ///   - path: A manifest field or package-relative file path.
    ///   - reason: A readable explanation of the expected value or file.
    init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}
