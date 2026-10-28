import SwiftUI
import Vault

/// Owns onboarding's navigation container and its RPC provider choice within the window's appearance environment.
struct OnboardingScene: View {
    @State private var navigation: OnboardingNavigation
    @State private var walletImport: ImportWalletModel
    @State private var walletSetup: WalletSetupModel
    /// The provider choice, shown after the wallet is saved; a new draft's onboarding starts with a new one.
    @State private var providers: ProvidersCoordinator
    let coordinator: any OnboardingCoordinating
    let pasteboard: any RecoveryCopying

    /// Seeds presentation once; the parent retains the coordinator and the pasteboard for the window's lifetime.
    /// - Parameters:
    ///   - coordinator: The owning window's preparation, persistence, and routing workflow.
    ///   - providers: New RPC provider choices and key entry, which onboarding keeps for as long as it stays.
    ///   - pasteboard: Copies a new wallet's recovery words to this device only, for a limited time.
    init(coordinator: any OnboardingCoordinating, providers: ProvidersCoordinator, pasteboard: any RecoveryCopying) {
        self.coordinator = coordinator
        self.providers = providers
        self.pasteboard = pasteboard
        let walletImport = ImportWalletModel(coordinator: coordinator)
        self.walletImport = walletImport
        walletSetup = WalletSetupModel(coordinator: coordinator, providers: providers)
        navigation = OnboardingNavigation(walletImport: walletImport, providers: providers)
    }

    var body: some View {
        let creation = walletSetup.creation
        let completion = walletSetup.completion
        NavigationStack(path: $navigation.stack) {
            WelcomeScreen(createWallet: {
                guard !walletImport.isPending, !walletImport.isPresented else { return }
                walletSetup.create()
            }, importWallet: {
                guard !walletSetup.isPending else { return }
                navigation.showImport()
            })
                .navigationDestination(for: OnboardingStep.self) { step in
                    Group {
                        switch step {
                        case .recovery:
                            RecoveryPhraseScreen(initialPhrase: coordinator.recovery?.phrase,
                                                 isSaved: coordinator.account != nil,
                                                 pasteboard: pasteboard,
                                                 continueSetup: walletSetup.save)
                        case .importWallet:
                            if let presentationID = walletImport.presentationID {
                                ImportWalletScreen(submission: walletImport)
                                    .importLifecycle(walletImport, presentationID: presentationID)
                                    .id(presentationID)
                            }
                        case .providers:
                            // The wallet is already saved, so its earlier steps no longer apply.
                            ProviderChoiceScreen(coordinator: providers, continueSetup: walletSetup.open)
                                .navigationBarBackButtonHidden()
                        case .providersRoute(let route):
                            ProvidersDestination(coordinator: providers, route: route)
                        }
                    }
                    .navigationSubtitle("Step \(step.number) of \(OnboardingStep.total)")
                }
        }
        .task(id: creation) { await walletSetup.prepare(creation) }
        .task(id: completion) { await walletSetup.complete(completion) }
        .onChange(of: walletSetup.isPrepared) { _, isPrepared in
            if isPrepared { navigation.path = [.recovery] }
        }
        .onChange(of: navigation.path.first) { previous, _ in
            // Back from the backup ends it and releases any draft no task still owns.
            if previous == .recovery { walletSetup.leaveBackup() }
        }
        .onChange(of: coordinator.account?.id) { showProviders() }
        .onChange(of: navigation.path.last) { showProviders() }
        .onDisappear {
            // Active work releases its draft after cancellation unwinds.
            if !coordinator.isWorking, !walletImport.isPending { walletSetup.discardDraft() }
        }
        // The provider choice's reads, changes, and prompts run while any onboarding step is on screen.
        .modifier(ProvidersLifecycle(coordinator: providers))
        .errorAlert($walletSetup.error)
    }

    /// Pushes the provider choice over the step that saved the wallet, and again if anything pops past it.
    ///
    /// Creation and import both end by saving the account; the saved wallet's earlier steps no longer apply.
    private func showProviders() {
        guard coordinator.account != nil, navigation.path.last != .providers else { return }
        navigation.path.append(.providers)
    }
}
