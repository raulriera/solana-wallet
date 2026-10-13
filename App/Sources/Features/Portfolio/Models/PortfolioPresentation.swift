import Portfolio

/// What the portfolio section shows for the coordinator's latest update.
nonisolated enum PortfolioPresentation: Equatable {
    /// No update yet; the first one arrives as soon as observation starts.
    case blank
    /// The first load is running and no holdings are available yet.
    case loading
    /// Holdings are available, including when the latest refresh failed.
    case holdings
    /// No holdings can show until the person acts on this failure.
    case unavailable(PortfolioError)

    /// Chooses the presentation; a failure that only provider setup fixes hides holdings, other failures don't.
    /// - Parameter update: The coordinator's latest update, or `nil` before the first one.
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
