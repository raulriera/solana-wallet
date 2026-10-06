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
    case unavailable(PortfolioFailure)

    /// Chooses the presentation; a missing or rejected key hides holdings, other failures don't.
    /// - Parameter update: The coordinator's latest update, or `nil` before the first one.
    init(_ update: Update?) {
        let failure = update?.error.map(PortfolioFailure.init)
        if let failure, failure.requiresProviderSetup {
            self = .unavailable(failure)
        } else if update?.snapshot != nil {
            self = .holdings
        } else if let failure {
            self = .unavailable(failure)
        } else {
            self = update == nil ? .blank : .loading
        }
    }
}
