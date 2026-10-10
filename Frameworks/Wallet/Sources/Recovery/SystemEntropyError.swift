/// A failure reported by the system's secure random number generator.
enum SystemEntropyError: Error, Equatable {
    /// The system couldn't generate random bytes.
    case unavailable(status: Int32)
}
