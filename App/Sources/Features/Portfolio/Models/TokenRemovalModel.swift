import Foundation
import Observation
import Portfolio
import RPC
import Transactions

/// Removes the tokens the person confirms from an account's list.
@MainActor
@Observable
final class TokenRemovalModel {
    var error: TokenRemovalError?
    /// The ID of the confirmed removal, while it waits or runs.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Address?

    /// Accepts a confirmed removal of a token.
    ///
    /// - Parameter mint: The mint address of the token to remove.
    func remove(_ mint: Address) {
        request = mint
        attempt = UUID()
    }

    /// Removes the requested token from an account's list.
    ///
    /// - Parameters:
    ///   - attempt: The ID of the attempt to run.
    ///   - portfolios: The store that saves the list.
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
            request = mint
            self.error = .saveFailed
        }
    }

    /// Retries removing the token whose save failed.
    func retry() {
        guard request != nil else { return }
        attempt = UUID()
    }
}
