import SwiftUI
import Vault

/// Owns onboarding's navigation container within the window's appearance environment.
struct OnboardingScene: View {
    @State private var isCreating = false
    @State private var isPresentingRecovery = false
    @State private var failure: String?
    let coordinator: any OnboardingCoordinating

    var body: some View {
        NavigationStack {
            // Import remains deferred until its screen's individual UX review.
            WelcomeScreen(createWallet: { isCreating = true }, importWallet: {})
                .navigationDestination(isPresented: $isPresentingRecovery) {
                    if let recovery = coordinator.recovery {
                        // Persistence and the app-content handoff are the next completion step.
                        RecoveryPhraseScreen(phrase: recovery.phrase, continueSetup: {})
                    }
                }
        }
        .task(id: isCreating) { await createWallet() }
        .onChange(of: isPresentingRecovery) {
            if !isPresentingRecovery { discardDraft() }
        }
        .onDisappear {
            // An active preparation discards its draft after cancellation unwinds.
            if !coordinator.isWorking { discardDraft() }
        }
        .alert("Wallet Creation Unavailable", item: $failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure)
        }
    }

    /// Prepares one draft and navigates only after cancellable derivation succeeds.
    private func createWallet() async {
        guard isCreating else { return }
        defer { isCreating = false }

        do {
            try await coordinator.create()
            try Task.checkCancellation()
            isPresentingRecovery = true
        } catch {
            if Task.isCancelled || error is CancellationError {
                discardDraft()
            } else {
                failure = String(localized: "Your wallet could not be prepared. Please try again.")
            }
        }
    }

    /// Releases the uncommitted recovery without reporting secret-bearing errors.
    private func discardDraft() {
        do { try coordinator.discard() }
        catch {
            failure = String(localized: "Wallet setup is still finishing. Please try again.")
        }
    }
}
