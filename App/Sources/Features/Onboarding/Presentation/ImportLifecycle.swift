import SwiftUI

/// Runs accepted imports while phrase entry is on screen.
private struct ImportLifecycle: ViewModifier {
    @Bindable var submission: ImportWalletModel
    let presentationID: UUID

    /// Awaits one non-secret attempt and releases its presentation when the destination leaves.
    /// - Parameter content: The existing phrase-entry screen.
    /// - Returns: The screen with cancellation and secret-free failure presentation.
    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .onDisappear { submission.leave(presentationID) }
            .errorAlert($submission.error)
    }
}

extension ImportWalletScreen {
    /// Runs accepted imports only while this destination owns their presentation.
    /// - Parameters:
    ///   - submission: The initiating window's import submission state.
    ///   - presentationID: This destination's identity, independent of recovery input.
    /// - Returns: The view with managed import work and failure presentation.
    func importLifecycle(_ submission: ImportWalletModel, presentationID: UUID) -> some View {
        modifier(ImportLifecycle(submission: submission, presentationID: presentationID))
    }
}
