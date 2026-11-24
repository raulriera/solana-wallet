/// An error for a request that needs an optional feature the provider doesn't declare.
public enum CapabilityError: Error, Sendable, Equatable {
    /// The provider doesn't declare the capability.
    case missing(Capabilities)
}
