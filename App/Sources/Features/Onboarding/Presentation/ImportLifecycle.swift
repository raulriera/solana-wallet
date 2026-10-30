import SwiftUI

/// Runs the waiting import while phrase entry is on screen and presents its errors.
private struct ImportLifecycle: ViewModifier {
    @Bindable var submission: ImportWalletModel
    let presentationID: UUID

    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .onDisappear { submission.leave(presentationID) }
            .errorAlert($submission.error)
    }
}

extension ImportWalletScreen {
    /// Runs the screen's waiting import and presents its errors.
    ///
    /// - Parameters:
    ///   - submission: The window's import model.
    ///   - presentationID: The identifier of this presentation.
    /// - Returns: The screen with the import lifecycle.
    func importLifecycle(_ submission: ImportWalletModel, presentationID: UUID) -> some View {
        modifier(ImportLifecycle(submission: submission, presentationID: presentationID))
    }
}
