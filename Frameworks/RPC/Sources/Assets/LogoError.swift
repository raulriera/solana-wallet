/// An error for an invalid logo lookup.
public enum LogoError: Error, Sendable, Equatable {
    /// The lookup has more than 50 mints.
    case tooManyMints
}
