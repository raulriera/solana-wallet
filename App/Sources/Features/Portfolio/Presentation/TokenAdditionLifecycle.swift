import SwiftUI

/// Binds lookups and adds to the add-token screen's lifetime without retaining task handles.
private struct TokenAdditionLifecycle: ViewModifier {
    @Bindable var addition: TokenAddition

    /// Runs the current lookup and accepted add, signals refusals, and presents failures.
    /// - Parameter content: The add-token screen.
    /// - Returns: The screen with managed lookups and adds, refusal feedback, and failure presentation.
    func body(content: Content) -> some View {
        let lookup = addition.lookup
        let attempt = addition.attempt
        content
            .task(id: lookup) { await addition.lookUp(lookup) }
            .task(id: attempt) { await addition.run(attempt) }
            .sensoryFeedback(.error, trigger: addition.refusalCount)
            .errorAlert($addition.error) { error in
                if error.canRetry {
                    Button("Try Again", action: addition.retry)
                }
                Button(error.canRetry ? "Cancel" : "OK", role: .cancel) {}
            }
    }
}

extension TokenAdditionScreen {
    /// Runs the screen's lookups and adds only while it is on screen.
    /// - Returns: The screen with managed lookups and adds, refusal feedback, and failure presentation.
    func tokenAdditionLifecycle() -> some View {
        modifier(TokenAdditionLifecycle(addition: addition))
    }
}
