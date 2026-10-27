import Foundation
import Observation
import Portfolio
import RPC
import Transactions

/// Owns one add-token sheet: it looks up the pasted address, then adds the token the person checked.
@MainActor
@Observable
final class TokenAdditionModel: Identifiable {
    /// The pasted text without the spaces and line breaks around it; a new address replaces the previous preview
    /// and starts a lookup.
    ///
    /// A rejection stays until the new address's lookup answers, so it changes in place.
    /// After a failed lookup, pasting the address again looks it up again; otherwise, pasting the same address
    /// keeps its preview or rejection without signaling again.
    private(set) var text = "" {
        didSet {
            guard address != (try? Address(oldValue)) || lookup == nil else { return }
            preview = nil
            if address == nil { rejection = nil }
            lookup = address.map { _ in UUID() }
        }
    }
    /// The token that the current address names, once the lookup finds it.
    private(set) var preview: TokenPreview?
    /// Why the pasted text can't be added, or `nil` while there's nothing to explain.
    private(set) var rejection: TokenRejection?
    /// Counts rejections, so each one signals again while the same rejection stays on screen.
    private(set) var rejectionCount = 0
    /// An error the person dismisses; trying again repeats the step that failed.
    var error: TokenAdditionError?
    /// The current address's lookup, or `nil` when the text isn't an address.
    private(set) var lookup: UUID?
    /// The accepted add, while it waits or runs.
    private(set) var attempt: UUID?
    /// Whether the previewed token is in the list; the sheet closes itself when it is.
    private(set) var isAdded = false

    /// The pasted address, or `nil` when the pasted text isn't one.
    var address: Address? { try? Address(text) }

    /// Takes pasted text, ignoring the spaces and line breaks that a copy can bring along.
    ///
    /// Text that isn't an address is rejected at once, without a lookup.
    /// - Parameter pasted: The pasteboard's text.
    func paste(_ pasted: String) {
        text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, address == nil {
            reject(.notAddress)
        }
    }

    /// Looks up the current address in the screen's SwiftUI-managed task; a newer address cancels it.
    ///
    /// A token that the wallet already lists is rejected without a request.
    /// - Parameters:
    ///   - lookup: The lookup captured by the owning view task.
    ///   - portfolios: The portfolios that every window shares, which look up tokens.
    ///   - account: The account whose list the token would join.
    ///   - network: The network to look the token up on.
    func lookUp(_ lookup: UUID?, in portfolios: PortfolioStore, for account: Account, on network: Network) async {
        guard let lookup, self.lookup == lookup, let address else { return }
        let holdings = portfolios.portfolio(for: account, on: network)?.holdings ?? []
        guard !holdings.contains(where: { $0.id == .asset(address.value) }) else {
            return reject(.alreadyListed)
        }
        do {
            let preview = try await portfolios.token(at: address, on: network)
            guard self.lookup == lookup, !Task.isCancelled else { return }
            self.preview = preview
            rejection = nil
        } catch {
            // A newer address or a closed sheet replaces this lookup's result.
            guard self.lookup == lookup, !Task.isCancelled, !(error is CancellationError) else { return }
            switch error {
            case TokenLookupError.notToken: reject(.notToken)
            case TokenLookupError.nonFungible: reject(.nonFungible)
            default:
                // Trying again can't help a rejected key, so pasting the address again looks it up instead.
                rejection = nil
                self.lookup = nil
                self.error = TokenAdditionError(lookup: PortfolioError(error))
            }
        }
    }

    /// Accepts the previewed token; taps while an add runs are ignored.
    func add() {
        guard preview != nil, attempt == nil else { return }
        attempt = UUID()
    }

    /// Adds the previewed token to a wallet's list in the screen's SwiftUI-managed task.
    /// - Parameters:
    ///   - attempt: The attempt captured by the owning view task.
    ///   - portfolios: The portfolios that every window shares, which save the wallet's list.
    ///   - account: The account whose list the token joins.
    ///   - network: The network whose list to change.
    func run(_ attempt: UUID?, in portfolios: PortfolioStore, for account: Account, on network: Network) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { self.attempt = nil }
        guard let token = preview?.token else { return }
        do {
            try await portfolios.add(token, for: account, on: network)
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

    /// Repeats the step that failed: the lookup when there's no preview yet, otherwise the add.
    func retry() {
        if preview == nil {
            lookup = address.map { _ in UUID() }
        } else {
            add()
        }
    }

    /// Records why the current address can't be added, and counts the rejection.
    /// - Parameter reason: Why the address can't be added.
    private func reject(_ reason: TokenRejection) {
        rejection = reason
        rejectionCount += 1
    }
}
