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
            .alert(error: $submission.error)
    }
}

extension ImportWalletScreen {
    /// Runs the screen's waiting import and presents its errors.
    ///
    /// - Parameter presentationID: The identifier of this presentation.
    /// - Returns: The screen with the import lifecycle.
    func importLifecycle(presentationID: UUID) -> some View {
        modifier(ImportLifecycle(submission: submission, presentationID: presentationID))
    }
}
