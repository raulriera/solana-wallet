import Accessibility
import Portfolio
import RPC
import SwiftUI
import Transactions

/// Runs an add-token screen's lookups and adds, and announces their results.
private struct TokenAdditionLifecycle: ViewModifier {
    @Environment(PortfolioStore.self) private var portfolios
    @Bindable var addition: TokenAdditionModel
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let lookup = addition.lookup
        let attempt = addition.attempt
        content
            .task(id: lookup) { await addition.lookUp(lookup, in: portfolios, for: account, on: network) }
            .task(id: attempt) { await addition.run(attempt, in: portfolios, for: account, on: network) }
            .sensoryFeedback(.error, trigger: addition.rejectionCount)
            .onChange(of: addition.rejectionCount) {
                guard let rejection = addition.rejection else { return }
                AccessibilityNotification.Announcement(String(localized: rejection.message)).post()
            }
            .onChange(of: addition.preview != nil) { _, isFound in
                guard isFound, let preview = addition.preview else { return }
                AccessibilityNotification.Announcement(String(localized: Self.announcement(for: preview))).post()
            }
            .alert(error: $addition.error, retry: addition.retry)
    }

    /// Returns the announcement for a found token.
    ///
    /// - Parameter preview: The token the lookup found.
    /// - Returns: The token's name or symbol, or a plain confirmation when it has neither.
    private static func announcement(for preview: TokenPreview) -> LocalizedStringResource {
        let metadata = preview.mint.metadata
        guard metadata?.name?.isEmpty == false || metadata?.symbol?.isEmpty == false else { return "Found a token." }
        return LocalizedStringResource("Found a token named \(Asset.token(preview.mint).displayName).",
                                       comment: "VoiceOver announcement after a pasted address is found. The variable is the token's name or symbol.")
    }
}

extension TokenAdditionScreen {
    /// Runs the screen's lookups and adds while it's on screen.
    ///
    /// - Parameters:
    ///   - account: The account whose list the token joins.
    ///   - network: The network whose list the token joins.
    /// - Returns: The screen with managed lookups and adds.
    func tokenAdditionLifecycle(for account: Account, on network: Network) -> some View {
        modifier(TokenAdditionLifecycle(addition: addition, account: account, network: network))
    }
}
