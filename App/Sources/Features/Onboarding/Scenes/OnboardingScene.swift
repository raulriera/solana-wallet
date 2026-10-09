import SwiftUI
import Vault

/// Owns onboarding's navigation container within the window's appearance environment.
struct OnboardingScene: View {
    @State private var isCreating = false
    @State private var isCompleting = false
    @State private var failure: String?
    @State private var navigation: OnboardingNavigation
    @State private var importSubmission: ImportSubmission
    @State private var providerSubmission: ProviderSubmission
    let coordinator: any OnboardingCoordinating
    let pasteboard: any RecoveryCopying

    /// Seeds presentation once; the parent retains these services for the window's lifetime.
    /// - Parameters:
    ///   - coordinator: The owning window's preparation, persistence, and routing workflow.
    ///   - connection: Verifies and saves the provider's API key after the wallet is saved.
    ///   - keyRevision: Tells every window when a key is saved.
    ///   - pasteboard: Copies a new wallet's recovery words to this device only, for a limited time.
    init(coordinator: any OnboardingCoordinating, connection: any ProviderConnecting, keyRevision: ProviderKeyRevision,
         pasteboard: any RecoveryCopying) {
        self.coordinator = coordinator
        self.pasteboard = pasteboard
        let importSubmission = ImportSubmission(coordinator: coordinator)
        self.importSubmission = importSubmission
        navigation = OnboardingNavigation(importSubmission: importSubmission)
        providerSubmission = ProviderSubmission(connection: connection, revision: keyRevision)
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            WelcomeScreen(createWallet: {
                guard !coordinator.isWorking, !isCreating, !isCompleting, !importSubmission.isPending,
                      !importSubmission.isPresented else { return }
                isCreating = true
            }, importWallet: {
                guard !isCreating, !isCompleting else { return }
                navigation.showImport()
            })
                .navigationDestination(for: OnboardingStep.self) { step in
                    Group {
                        switch step {
                        case .recovery:
                            RecoveryPhraseScreen(initialPhrase: coordinator.recovery?.phrase,
                                                 isSaved: coordinator.account != nil,
                                                 pasteboard: pasteboard,
                                                 continueSetup: { isCompleting = true })
                        case .importWallet:
                            if let presentationID = importSubmission.presentationID {
                                ImportWalletScreen(submission: importSubmission)
                                    .importLifecycle(importSubmission, presentationID: presentationID)
                                    .id(presentationID)
                            }
                        case .providerSetup:
                            // The wallet is already saved, so its earlier steps no longer apply.
                            ProviderSetupScreen(isKeyRejected: providerSubmission.isKeyRejected,
                                                submit: providerSubmission.submit)
                                .providerSetupLifecycle(providerSubmission)
                                .navigationBarBackButtonHidden()
                        }
                    }
                    .navigationSubtitle("Step \(step.number) of \(OnboardingStep.total)")
                }
        }
        .task(id: isCreating) { await createWallet() }
        .task(id: isCompleting) { await completeWallet() }
        .onChange(of: navigation.path.first) { previous, _ in
            // Back from the backup ends it; release any draft no task still owns.
            guard previous == .recovery else { return }
            isCompleting = false
            if !coordinator.isWorking { discardDraft() }
        }
        .onChange(of: coordinator.account?.id) { showProviderSetup() }
        .onChange(of: navigation.path.last) { showProviderSetup() }
        .onChange(of: providerSubmission.isSaved) { openWallet() }
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
            navigation.path = [.recovery]
        } catch {
            if Task.isCancelled || error is CancellationError {
                discardDraft()
            } else {
                failure = String(localized: "Your wallet could not be prepared. Please try again.")
            }
        }
    }

    /// Opens the saved wallet once its provider key is saved.
    private func openWallet() {
        do { try coordinator.finish() }
        catch {
            failure = String(localized: "Your wallet could not be opened. Please try again.")
        }
    }

    /// Pushes provider setup over the step that saved the wallet, and again if anything pops past it.
    ///
    /// Creation and import both end by saving the account; the saved wallet's earlier steps no longer apply.
    private func showProviderSetup() {
        guard coordinator.account != nil, navigation.path.last != .providerSetup else { return }
        navigation.path.append(.providerSetup)
    }

    /// Releases the uncommitted recovery without reporting secret-bearing errors.
    private func discardDraft() {
        do { try coordinator.discard() }
        catch {
            failure = String(localized: "Wallet setup is still finishing. Please try again.")
        }
    }
}
