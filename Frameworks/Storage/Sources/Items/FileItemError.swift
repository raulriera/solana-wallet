/// An error from a file item.
public enum FileItemError: Error, Equatable {
    /// The file's bytes don't decode to a value.
    case unreadable
    /// The value's bytes don't decode back to an equal value.
    case unencodable
}
