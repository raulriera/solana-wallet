import SwiftUI

/// Keeps the Providers screen's choice current, runs each choice, and presents key entry and failures.
private struct ProvidersLifecycle: ViewModifier {
    @Bindable var flow: ProvidersFlow

    /// Reads the choice whenever any window changes it and awaits one choice at a time.
    /// - Parameter content: The Providers screen.
    /// - Returns: The screen with managed reads, choices, key entry, and failure presentation.
    func body(content: Content) -> some View {
        let attempt = flow.attempt
        content
            .task(id: flow.revision.value) { await flow.reload() }
            .task(id: attempt) { await flow.run(attempt) }
            .sheet(item: $flow.keyEntry) { submission in
                // The sheet closes itself after a saved key; the choice that asked for the key continues.
                ProviderSetupSheet(submission: submission)
                    .onChange(of: submission.isSaved) { flow.keySaved() }
            }
            .errorAlert($flow.error)
    }
}

extension ProvidersScreen {
    /// Runs the Providers flow's reads and choices only while this screen is on screen.
    /// - Parameter flow: The owning window's Providers flow.
    /// - Returns: The screen with managed reads, choices, key entry, and failure presentation.
    func providersLifecycle(_ flow: ProvidersFlow) -> some View {
        modifier(ProvidersLifecycle(flow: flow))
    }
}
