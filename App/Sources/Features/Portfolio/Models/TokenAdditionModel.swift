import Foundation
import Observation
import Portfolio
import RPC
import Transactions

/// Looks up a pasted token address, then adds the token to an account's list.
@MainActor
@Observable
final class TokenAdditionModel: Identifiable {
    /// The pasted text without the spaces and line breaks around it.
    private(set) var text = "" {
        didSet {
            guard address != (try? Address(oldValue)) || lookup == nil else { return }
            preview = nil
            if address == nil { rejection = nil }
            lookup = address.map { _ in UUID() }
        }
    }
    /// The looked-up token, or `nil` until the lookup finds it.
    private(set) var preview: TokenPreview?
    private(set) var rejection: TokenRejection?
    private(set) var rejectionCount = 0
    var error: TokenAdditionError?
    /// The ID of the current address's lookup, or `nil` when there's nothing to look up.
    private(set) var lookup: UUID?
    /// The ID of the accepted add, while it waits or runs.
    private(set) var attempt: UUID?
    private(set) var isAdded = false

    var address: Address? { try? Address(text) }

    /// Takes pasted text and rejects it when it isn't an address.
    ///
    /// - Parameter pasted: The pasteboard's text.
    func paste(_ pasted: String) {
        text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, address == nil {
            reject(.notAddress)
        }
    }

    /// Looks up the token at the current address.
    ///
    /// - Parameters:
    ///   - lookup: The ID of the lookup to run.
    ///   - portfolios: The store that looks up tokens.
    ///   - account: The account whose list the token would join.
    ///   - network: The network to look the token up on.
    func lookUp(_ lookup: UUID?, in portfolios: PortfolioStore, for account: Account, on network: Network) async {
        guard let lookup, self.lookup == lookup, let address else { return }
        let holdings = portfolios.portfolio(for: account, on: network)?.holdings ?? []
        guard !holdings.contains(where: { $0.id == .token(mint: address) }) else {
            return reject(.alreadyListed)
        }
        do {
            let preview = try await portfolios.token(at: address, on: network)
            guard self.lookup == lookup, !Task.isCancelled else { return }
            self.preview = preview
            rejection = nil
        } catch {
            guard self.lookup == lookup, !Task.isCancelled, !(error is CancellationError) else { return }
            switch error {
            case TokenLookupError.notToken: reject(.notToken)
            case TokenLookupError.nonFungible: reject(.nonFungible)
            default:
                rejection = nil
                self.lookup = nil
                self.error = TokenAdditionError(lookup: PortfolioError(error))
            }
        }
    }

    /// Accepts the previewed token for adding.
    func add() {
        guard preview != nil, attempt == nil else { return }
        attempt = UUID()
    }

    /// Adds the previewed token to an account's list.
    ///
    /// - Parameters:
    ///   - attempt: The ID of the attempt to run.
    ///   - portfolios: The store that saves the list.
    ///   - account: The account whose list the token joins.
    ///   - network: The network whose list to change.
    func run(_ attempt: UUID?, in portfolios: PortfolioStore, for account: Account, on network: Network) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { self.attempt = nil }
        guard let mint = preview?.mint else { return }
        do {
            try await portfolios.add(mint, for: account, on: network)
            isAdded = true
        } catch TokenListError.limitReached {
            self.error = .limitReached
        } catch TokenListError.unreadable {
            self.error = .listUnreadable
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = .saveFailed
        }
    }

    /// Repeats the step that failed: the lookup when there's no preview yet, or else the add.
    func retry() {
        if preview == nil {
            lookup = address.map { _ in UUID() }
        } else {
            add()
        }
    }

    /// Records why the current address can't be added, and counts the rejection.
    ///
    /// - Parameter reason: Why the address can't be added.
    private func reject(_ reason: TokenRejection) {
        rejection = reason
        rejectionCount += 1
    }
}
