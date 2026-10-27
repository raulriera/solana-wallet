import Foundation
import Observation
import Portfolio
import RPC
import Transactions

/// Owns one portfolio's token removals: it removes each token the person confirms and explains a failed save.
@MainActor
@Observable
final class TokenRemovalModel {
    /// Why the last removal couldn't be saved; the token stays in the list.
    var error: TokenRemovalError?
    /// The confirmed removal, while it waits for the scene's task or runs.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Address?

    /// Accepts a confirmed removal; the scene's task removes the token.
    ///
    /// Native SOL always stays, so asking to remove it does nothing.
    /// - Parameter token: The token to remove.
    func remove(_ token: Holding.Identity) {
        guard case .asset(let mint) = token, let address = try? Address(mint) else { return }
        request = address
        attempt = UUID()
    }

    /// Removes the requested token from a wallet's list once, in the scene's SwiftUI-managed task.
    ///
    /// The save can't stop partway, so an error is explained even when the task is cancelled.
    /// - Parameters:
    ///   - attempt: The attempt captured by the owning view task.
    ///   - portfolios: The portfolios that every window shares, which save the wallet's list.
    ///   - account: The account whose list to change.
    ///   - network: The network whose list to change.
    func run(_ attempt: UUID?, in portfolios: PortfolioStore, for account: Account, on network: Network) async {
        guard let attempt, self.attempt == attempt, let mint = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await portfolios.remove(mint, for: account, on: network)
        } catch TokenListError.unreadable {
            self.error = .listUnreadable
        } catch {
            // Trying again removes the same token.
            request = mint
            self.error = .saveFailed
        }
    }

    /// Removes the token whose save failed again; the scene's task runs the new attempt.
    func retry() {
        guard request != nil else { return }
        attempt = UUID()
    }
}
