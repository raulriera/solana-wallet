import SwiftUI

/// Binds accepted entry checks to their screen's lifetime without retaining task handles.
private struct ProviderSubmissionLifecycle<EntryError: ProviderEntryError>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Bindable var submission: ProviderSubmission<EntryError>

    /// Awaits one entry check, signals each refused entry, presents its secret-free failure, and closes the screen
    /// once the entry is saved.
    /// - Parameter content: The entry screen.
    /// - Returns: The screen with managed entry checks, rejection feedback, failure presentation, and closing.
    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .sensoryFeedback(.error, trigger: submission.rejectionCount)
            .errorAlert($submission.error)
            .onChange(of: submission.isSaved) { dismiss() }
    }
}

extension ProviderSetupScreen {
    /// Runs accepted entry checks only while this screen is on screen, and closes it once the entry is saved.
    /// - Parameter submission: The owning window's checks of an API key or a custom RPC URL.
    /// - Returns: The screen with managed entry checks, rejection feedback, failure presentation, and closing.
    func providerSetupLifecycle<EntryError: ProviderEntryError>(_ submission: ProviderSubmission<EntryError>) -> some View {
        modifier(ProviderSubmissionLifecycle(submission: submission))
    }
}
