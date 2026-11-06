/// An error from using the chosen price provider.
nonisolated enum PriceProviderError: Error, Equatable {
    /// The saved custom price server URL can't be used.
    case unusableServer
}
