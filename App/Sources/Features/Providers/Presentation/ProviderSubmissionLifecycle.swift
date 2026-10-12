import SwiftUI

/// Binds accepted entry checks to their screen's lifetime without retaining task handles.
private struct ProviderSubmissionLifecycle<EntryError: ProviderEntryError>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Bindable var submission: ProviderSubmission<EntryError>
    /// Whether the screen closes itself once its entry is saved; other presenters continue instead.
    let closesWhenSaved: Bool

    /// Awaits one entry check, signals each refused entry, presents its secret-free failure, and closes the screen
    /// once the entry is saved when `closesWhenSaved` is set.
    /// - Parameter content: The entry screen.
    /// - Returns: The screen with managed entry checks, rejection feedback, failure presentation, and closing when set.
    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .sensoryFeedback(.error, trigger: submission.rejectionCount)
            .errorAlert($submission.error)
            .onChange(of: submission.isSaved) { if closesWhenSaved { dismiss() } }
    }
}

extension ProviderSetupScreen {
    /// Runs accepted key checks only while this screen is on screen.
    /// - Parameters:
    ///   - submission: The owning window's provider key checks.
    ///   - closesWhenSaved: Whether the screen closes itself once the key is saved, as a pushed screen does.
    /// - Returns: The screen with managed key checks, rejection feedback, failure presentation, and closing when set.
    func providerSetupLifecycle(_ submission: ProviderSubmission<ProviderConnectionError>,
                                closesWhenSaved: Bool = false) -> some View {
        modifier(ProviderSubmissionLifecycle(submission: submission, closesWhenSaved: closesWhenSaved))
    }
}

extension CustomRPCSetupScreen {
    /// Runs accepted URL checks only while this screen is on screen, and closes it once the RPC is saved.
    /// - Parameter submission: The owning window's custom RPC checks.
    /// - Returns: The screen with managed URL checks, rejection feedback, failure presentation, and closing.
    func customRPCSetupLifecycle(_ submission: ProviderSubmission<CustomRPCError>) -> some View {
        modifier(ProviderSubmissionLifecycle(submission: submission, closesWhenSaved: true))
    }
}
