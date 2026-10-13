import Accessibility
import SwiftUI

/// Binds accepted entry checks to their screen's lifetime without retaining task handles, and announces rejections.
private struct ProviderSetupLifecycle<EntryError: ProviderEntryError>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Bindable var submission: ProviderSetupModel<EntryError>

    /// Awaits one entry check, signals and announces each rejected entry, presents its secret-free failure, and
    /// closes the screen once the entry is saved.
    /// - Parameter content: The entry screen.
    /// - Returns: The screen with managed entry checks, rejection feedback, failure presentation, and closing.
    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .sensoryFeedback(.error, trigger: submission.rejectionCount)
            .onChange(of: submission.rejectionCount) {
                guard let rejection = submission.rejection else { return }
                AccessibilityNotification.Announcement(String(localized: rejection.message)).post()
            }
            .errorAlert($submission.error)
            .onChange(of: submission.isSaved) { dismiss() }
    }
}

extension ProviderSetupScreen {
    /// Runs accepted entry checks only while this screen is on screen, and closes it once the entry is saved.
    /// - Returns: The screen with managed entry checks, rejection feedback, failure presentation, and closing.
    func providerSetupLifecycle<EntryError: ProviderEntryError>() -> some View
    where Submission == ProviderSetupModel<EntryError> {
        modifier(ProviderSetupLifecycle(submission: submission))
    }
}
