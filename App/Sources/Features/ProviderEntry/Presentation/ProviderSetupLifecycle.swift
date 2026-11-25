import Accessibility
import SwiftUI

/// Runs a screen's accepted entry checks, announces rejections, and closes the screen once the entry is saved.
private struct ProviderSetupLifecycle<EntryError: ProviderEntryError>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Bindable var submission: ProviderSetupModel<EntryError>

    func body(content: Content) -> some View {
        let attempt = submission.attempt
        content
            .task(id: attempt) { await submission.run(attempt) }
            .sensoryFeedback(.error, trigger: submission.rejectionCount)
            .onChange(of: submission.rejectionCount) {
                guard let rejection = submission.rejection else { return }
                AccessibilityNotification.Announcement(String(localized: rejection.message)).post()
            }
            .alert(error: $submission.error)
            .onChange(of: submission.isSaved) { dismiss() }
    }
}

/// A screen that collects a provider entry for a setup model.
protocol ProviderSetupScreen: View {
    /// The error for a rejected or failed entry.
    associatedtype EntryError: ProviderEntryError

    /// The model that checks and saves the entry.
    var submission: ProviderSetupModel<EntryError> { get }
}

extension ProviderSetupScreen {
    /// Runs the screen's accepted entry checks and closes it once the entry is saved.
    ///
    /// - Returns: The screen with managed entry checks.
    func providerSetupLifecycle() -> some View {
        modifier(ProviderSetupLifecycle(submission: submission))
    }
}
