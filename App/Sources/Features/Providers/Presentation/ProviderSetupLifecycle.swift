import SwiftUI

/// Binds accepted key checks to the provider setup screen's lifetime without retaining task handles.
private struct ProviderSetupLifecycle: ViewModifier {
    @Bindable var submission: ProviderSubmission

    /// Awaits one key check, signals each rejected key, and presents its secret-free failure.
    /// - Parameter content: The provider setup screen.
    /// - Returns: The screen with managed key checks, rejection feedback, and failure presentation.
    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .sensoryFeedback(.error, trigger: submission.rejectionCount)
            .errorAlert($submission.error)
    }
}

extension ProviderSetupScreen {
    /// Runs accepted key checks only while this screen is on screen.
    /// - Parameter submission: The owning window's provider key checks.
    /// - Returns: The screen with managed key checks, rejection feedback, and failure presentation.
    func providerSetupLifecycle(_ submission: ProviderSubmission) -> some View {
        modifier(ProviderSetupLifecycle(submission: submission))
    }
}
