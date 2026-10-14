import Observation
@testable import widgets

/// Holds the portfolio that a hosted window shows, so a test can replace it as a network change does.
@MainActor
@Observable
final class ShownPortfolio {
    /// The portfolio presentation that the hosted window observes.
    var coordinator: any PortfolioCoordinating

    /// Starts the hosted window on a portfolio.
    /// - Parameter coordinator: The portfolio presentation that the window shows first.
    init(_ coordinator: any PortfolioCoordinating) {
        self.coordinator = coordinator
    }
}
