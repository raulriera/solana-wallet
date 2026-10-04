import SwiftUI
import Vault

/// Owns onboarding's navigation container within the window's appearance environment.
struct OnboardingScene: View {
    @State private var isCreating = false
    @State private var isCompleting = false
    @State private var isPresentingRecovery = false
    @State private var failure: String?
    @State private var importSubmission: ImportSubmission
    let coordinator: any OnboardingCoordinating

    /// Seeds import presentation once; the parent retains this coordinator for the window's lifetime.
    /// - Parameter coordinator: The owning window's preparation, persistence, and routing workflow.
    init(coordinator: any OnboardingCoordinating) {
        self.coordinator = coordinator
        importSubmission = ImportSubmission(coordinator: coordinator)
    }

    var body: some View {
        @Bindable var importSubmission = importSubmission
        NavigationStack {
            WelcomeScreen(createWallet: {
                guard !coordinator.isWorking, !isCreating, !isCompleting, !importSubmission.isPending,
                      !importSubmission.isPresented else { return }
                isCreating = true
            }, importWallet: {
                guard !isCreating, !isCompleting, !isPresentingRecovery else { return }
                importSubmission.present()
            })
                .navigationDestination(isPresented: $isPresentingRecovery) {
                    if let recovery = coordinator.recovery {
                        RecoveryPhraseScreen(phrase: recovery.phrase, continueSetup: { isCompleting = true })
                    }
                }
                .navigationDestination(isPresented: $importSubmission.isPresented) {
                    if let presentationID = importSubmission.presentationID {
                        ImportWalletScreen(submission: importSubmission)
                            .importLifecycle(importSubmission, presentationID: presentationID)
                            .id(presentationID)
                    }
                }
        }
        .task(id: isCreating) { await createWallet() }
        .task(id: isCompleting) { await completeWallet() }
        .onChange(of: isPresentingRecovery) {
            if !isPresentingRecovery {
                isCompleting = false
                if !coordinator.isWorking { discardDraft() }
            }
        }
        .onDisappear {
            // Active work releases its draft after cancellation unwinds.
            if !coordinator.isWorking, !importSubmission.isPending { discardDraft() }
        }
        .alert("Wallet Setup Unavailable", item: $failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure)
        }
    }

    /// Saves only after backup confirmation; failures preserve the draft for another attempt.
    private func completeWallet() async {
        guard isCompleting else { return }
        defer {
            isCompleting = false
            if Task.isCancelled { discardDraft() }
        }

        do { _ = try await coordinator.complete() }
        catch {
            if !Task.isCancelled, !(error is CancellationError) {
                failure = String(localized: "Your wallet could not be saved. Your recovery words are still available. Please try again.")
            }
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
