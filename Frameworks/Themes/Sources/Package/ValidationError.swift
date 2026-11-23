/// A package error at a manifest field or package file.
public struct ValidationError: Error, Sendable, Equatable {
    /// What is wrong with the field or file.
    enum Kind: Sendable {
        /// The value is missing, malformed, or of the wrong type.
        case invalid
        /// The value names a format version or option that this version doesn't know.
        case unsupported
        /// The file or directory can't be read as what the package needs.
        case unreadable
        /// The file exceeds a byte or pixel limit.
        case tooLarge
    }

    let path: String
    let kind: Kind

    /// Creates a package error.
    ///
    /// - Parameters:
    ///   - path: A manifest field or package-relative file path.
    ///   - kind: What is wrong with the field or file.
    init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}
