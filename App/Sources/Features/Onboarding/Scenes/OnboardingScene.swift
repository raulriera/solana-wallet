import SwiftUI
import Vault

/// Owns onboarding's navigation container within the window's appearance environment.
struct OnboardingScene: View {
    @State private var isCreating = false
    @State private var isCompleting = false
    @State private var error: OnboardingError?
    @State private var navigation: OnboardingNavigation
    @State private var walletImport: ImportWalletModel
    let coordinator: any OnboardingCoordinating
    let providers: ProvidersCoordinator
    let pasteboard: any RecoveryCopying

    /// Seeds presentation once; the parent retains these services for the window's lifetime.
    /// - Parameters:
    ///   - coordinator: The owning window's preparation, persistence, and routing workflow.
    ///   - providers: The window's RPC provider choice, shown after the wallet is saved; `onboardingLifecycle()` runs
    ///     its work.
    ///   - pasteboard: Copies a new wallet's recovery words to this device only, for a limited time.
    init(coordinator: any OnboardingCoordinating, providers: ProvidersCoordinator, pasteboard: any RecoveryCopying) {
        self.coordinator = coordinator
        self.providers = providers
        self.pasteboard = pasteboard
        let walletImport = ImportWalletModel(coordinator: coordinator)
        self.walletImport = walletImport
        navigation = OnboardingNavigation(walletImport: walletImport, providers: providers)
    }

    var body: some View {
        NavigationStack(path: $navigation.stack) {
            WelcomeScreen(createWallet: {
                guard !coordinator.isWorking, !isCreating, !isCompleting, !walletImport.isPending,
                      !walletImport.isPresented else { return }
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
                            if let presentationID = walletImport.presentationID {
                                ImportWalletScreen(submission: walletImport)
                                    .importLifecycle(walletImport, presentationID: presentationID)
                                    .id(presentationID)
                            }
                        case .providers:
                            // The wallet is already saved, so its earlier steps no longer apply.
                            ProviderChoiceScreen(coordinator: providers, continueSetup: openWallet)
                                .navigationBarBackButtonHidden()
                        case .providersRoute(let route):
                            ProvidersDestination(coordinator: providers, route: route)
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
        .onChange(of: coordinator.account?.id) { showProviders() }
        .onChange(of: navigation.path.last) { showProviders() }
        .onDisappear {
            // Active work releases its draft after cancellation unwinds.
            if !coordinator.isWorking, !walletImport.isPending { discardDraft() }
        }
        .errorAlert($error)
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
                self.error = .saveFailed
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
                self.error = .preparationFailed
            }
        }
    }

    /// Opens the saved wallet with the provider in use.
    ///
    /// Taps while a provider change waits to be saved are ignored, so the wallet never opens on the previous provider.
    /// Saving a choice is quick, so the button shows no waiting state.
    private func openWallet() {
        guard providers.attempt == nil else { return }
        do { try coordinator.finish() }
        catch {
            self.error = .openFailed
        }
    }

    /// Pushes the provider choice over the step that saved the wallet, and again if anything pops past it.
    ///
    /// Creation and import both end by saving the account; the saved wallet's earlier steps no longer apply.
    private func showProviders() {
        guard coordinator.account != nil, navigation.path.last != .providers else { return }
        navigation.path.append(.providers)
    }

    /// Releases the uncommitted recovery without reporting secret-bearing errors.
    private func discardDraft() {
        do { try coordinator.discard() }
        catch {
            self.error = .stillFinishing
        }
    }
}
