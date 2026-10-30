/// A package error at a manifest field or package file.
public struct ValidationError: Error, Sendable, Equatable {
    let path: String
    let reason: String

    /// Creates a package error.
    ///
    /// - Parameters:
    ///   - path: A manifest field or package-relative file path.
    ///   - reason: A readable explanation of the expected value or file.
    init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}
