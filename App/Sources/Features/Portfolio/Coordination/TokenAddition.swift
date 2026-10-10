import Accessibility
import Foundation
import Observation
import Portfolio
import SwiftUI
import Transactions

/// Owns one window's add-token sheet: it looks up the pasted address, then adds the token the person checked.
@MainActor
@Observable
final class TokenAddition: Identifiable {
    /// The pasted text without the spaces and line breaks around it; a new address replaces the previous preview
    /// and starts a lookup.
    ///
    /// A refusal stays until the new address's lookup answers, so its message changes in place.
    /// After a failed lookup, pasting the address again looks it up again; otherwise, pasting the same address
    /// keeps its preview or refusal without signaling again.
    private(set) var text = "" {
        didSet {
            guard address != (try? Address(oldValue)) || lookup == nil else { return }
            preview = nil
            if address == nil { message = nil }
            lookup = address.map { _ in UUID() }
        }
    }
    /// The token that the current address names, once the lookup finds it.
    private(set) var preview: TokenPreview?
    /// Why the pasted text can't be added, shown under it, or `nil` while there's nothing to explain.
    private(set) var message: LocalizedStringResource?
    /// Counts refusals, so each one signals again while its message stays on screen.
    private(set) var refusalCount = 0
    /// An error the person dismisses; trying again repeats the step that failed.
    var error: TokenAdditionError?
    /// The current address's lookup, or `nil` when the text isn't an address.
    private(set) var lookup: UUID?
    /// The accepted add, while it waits or runs.
    private(set) var attempt: UUID?
    /// Whether the previewed token is in the list; the sheet closes itself when it is.
    private(set) var isAdded = false
    private let coordinator: any PortfolioCoordinating

    /// Works with the window's portfolio.
    /// - Parameter coordinator: The window's portfolio, which looks up tokens and adds them to its wallet's list.
    init(coordinator: any PortfolioCoordinating) {
        self.coordinator = coordinator
    }

    /// The pasted address, or `nil` when the pasted text isn't one.
    var address: Address? { try? Address(text) }

    /// Takes pasted text, ignoring the spaces and line breaks that a copy can bring along.
    ///
    /// Text that isn't an address is refused at once, without a lookup.
    /// - Parameter pasted: The pasteboard's text.
    func paste(_ pasted: String) {
        withAnimation { text = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !text.isEmpty, address == nil {
            refuse("This isn't a valid address.")
        }
    }

    /// Looks up the current address in the screen's SwiftUI-managed task; a newer address cancels it.
    ///
    /// A token that's already listed is refused without a request.
    /// - Parameter lookup: The lookup captured by the owning view task.
    func lookUp(_ lookup: UUID?) async {
        guard let lookup, self.lookup == lookup, let address else { return }
        guard !coordinator.holdings.contains(where: { $0.id == .asset(address.value) }) else {
            return refuse("This token is already in your list.")
        }
        do {
            let preview = try await coordinator.token(at: address)
            guard self.lookup == lookup, !Task.isCancelled else { return }
            withAnimation {
                self.preview = preview
                message = nil
            }
            AccessibilityNotification.Announcement(String(localized: Self.announcement(for: preview))).post()
        } catch {
            // A newer address or a closed sheet replaces this lookup's result.
            guard self.lookup == lookup, !Task.isCancelled, !(error is CancellationError) else { return }
            switch error {
            case TokenLookupError.notToken: refuse("This address isn't a token.")
            case TokenLookupError.nonFungible: refuse("NFTs can't be added yet.")
            default:
                // Trying again can't help a rejected key, so pasting the address again looks it up instead.
                withAnimation { message = nil }
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

    /// Adds the previewed token in the screen's SwiftUI-managed task.
    /// - Parameter attempt: The attempt captured by the owning view task.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { self.attempt = nil }
        guard let token = preview?.token else { return }
        do {
            try await coordinator.add(token)
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

    /// Explains why the current address can't be added, with an error signal and a VoiceOver announcement.
    /// - Parameter reason: The explanation shown under the pasted text.
    private func refuse(_ reason: LocalizedStringResource) {
        withAnimation { message = reason }
        refusalCount += 1
        AccessibilityNotification.Announcement(String(localized: reason)).post()
    }

    /// Tells VoiceOver which token the address names, without reading out the address itself.
    /// - Parameter preview: The token the lookup found.
    /// - Returns: The token's claimed name or symbol, or a plain confirmation when it has neither.
    private static func announcement(for preview: TokenPreview) -> LocalizedStringResource {
        let token = Holding(preview: preview)
        guard token.name?.isEmpty == false || token.symbol?.isEmpty == false else { return "Found a token." }
        return "Found a token named \(token.displayName)."
    }
}
