/// An error from reading the price provider choice or using its custom server.
nonisolated enum PricesError: Error, Equatable {
    /// The price provider choice can't be read.
    case settingsUnreadable
    /// The saved custom price server URL can't be used.
    case unusableServer
}
