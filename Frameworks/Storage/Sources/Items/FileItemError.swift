/// A file storage error that never contains the stored value.
public enum FileItemError: Error, Equatable {
    /// The file's bytes don't represent a value of the item's type.
    case unreadable
    /// The value's bytes don't decode back to an equal value, so the value wasn't saved.
    case unencodable
}
