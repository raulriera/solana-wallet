import Foundation
import Observation
import Portfolio
import Transactions

/// Owns one window's token removals: it removes each token the person confirms and explains a failed save.
@MainActor
@Observable
final class TokenRemovalModel {
    /// Why the last removal couldn't be saved; the token stays in the list.
    var error: TokenRemovalError?
    /// The confirmed removal, while it waits for the scene's task or runs.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Address?
    private let coordinator: any PortfolioCoordinating

    /// Works with the window's portfolio.
    /// - Parameter coordinator: The window's portfolio, which removes tokens from its wallet's list.
    init(coordinator: any PortfolioCoordinating) {
        self.coordinator = coordinator
    }

    /// Accepts a confirmed removal; the scene's task removes the token.
    ///
    /// Native SOL always stays, so asking to remove it does nothing.
    /// - Parameter holding: The token to remove.
    func remove(_ holding: Holding) {
        guard case .asset(let mint) = holding.id, let address = try? Address(mint) else { return }
        request = address
        attempt = UUID()
    }

    /// Removes the requested token once in the scene's SwiftUI-managed task.
    ///
    /// The save can't stop partway, so an error is explained even when the task is cancelled.
    /// - Parameter attempt: The attempt captured by the owning view task.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let mint = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await coordinator.remove(mint)
        } catch TokenListError.unreadable {
            self.error = .listUnreadable
        } catch {
            self.error = .saveFailed
        }
    }
}
