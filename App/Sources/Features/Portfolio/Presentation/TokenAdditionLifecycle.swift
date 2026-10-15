import Accessibility
import Portfolio
import SwiftUI

/// Binds lookups and adds to the add-token screen's lifetime without retaining task handles, and announces their results.
private struct TokenAdditionLifecycle: ViewModifier {
    @Bindable var addition: TokenAdditionModel

    /// Runs the current lookup and accepted add, signals rejections and found tokens, and presents failures.
    /// - Parameter content: The add-token screen.
    /// - Returns: The screen with managed lookups and adds, rejection feedback, announcements, and failure
    ///   presentation.
    func body(content: Content) -> some View {
        let lookup = addition.lookup
        let attempt = addition.attempt
        content
            .task(id: lookup) { await addition.lookUp(lookup) }
            .task(id: attempt) { await addition.run(attempt) }
            .sensoryFeedback(.error, trigger: addition.rejectionCount)
            .onChange(of: addition.rejectionCount) {
                guard let rejection = addition.rejection else { return }
                AccessibilityNotification.Announcement(String(localized: rejection.message)).post()
            }
            // A new address clears the previous preview first, so each found token appears from nothing.
            .onChange(of: addition.preview != nil) { _, isFound in
                guard isFound, let preview = addition.preview else { return }
                AccessibilityNotification.Announcement(String(localized: Self.announcement(for: preview))).post()
            }
            .errorAlert($addition.error, retry: addition.retry)
    }

    /// Tells VoiceOver which token the address names, without reading out the address itself.
    /// - Parameter preview: The token the lookup found.
    /// - Returns: The token's claimed name or symbol, or a plain confirmation when it has neither.
    private static func announcement(for preview: TokenPreview) -> LocalizedStringResource {
        let token = Holding(preview: preview)
        guard token.name?.isEmpty == false || token.symbol?.isEmpty == false else { return "Found a token." }
        return LocalizedStringResource("Found a token named \(token.displayName).",
                                       comment: "VoiceOver announcement after a pasted address is found. The variable is the token's name or symbol.")
    }
}

extension TokenAdditionScreen {
    /// Runs the screen's lookups and adds only while it is on screen.
    /// - Returns: The screen with managed lookups and adds, rejection feedback, announcements, and failure
    ///   presentation.
    func tokenAdditionLifecycle() -> some View {
        modifier(TokenAdditionLifecycle(addition: addition))
    }
}
