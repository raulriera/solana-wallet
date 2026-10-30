import Portfolio

/// What the portfolio shows for a wallet's latest update.
nonisolated enum PortfolioPresentation: Equatable {
    /// No update has arrived yet.
    case blank
    /// The first load is running.
    case loading
    /// Holdings are available, even if the latest refresh failed.
    case holdings
    /// An error hides the holdings.
    case unavailable(PortfolioError)

    /// Creates the presentation for a wallet's latest update.
    ///
    /// - Parameter update: The wallet's latest update, or `nil` before the first one.
    init(_ update: Update?) {
        let error = update?.error.map(PortfolioError.init)
        if let error, error.requiresProviderSetup {
            self = .unavailable(error)
        } else if update?.snapshot != nil {
            self = .holdings
        } else if let error {
            self = .unavailable(error)
        } else {
            self = update == nil ? .blank : .loading
        }
    }
}
