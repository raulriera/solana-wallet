import SwiftUI
import Vault

/// Shows onboarding's steps, from welcome to the RPC provider choice.
struct OnboardingScene: View {
    @State private var navigation: OnboardingNavigation
    @State private var walletImport: ImportWalletModel
    @State private var walletSetup: WalletSetupModel
    @State private var coordinator: any OnboardingCoordinating
    @State private var providers: ProvidersCoordinator
    @Binding var account: Account?
    let pasteboard: any RecoveryCopying

    /// Creates an onboarding scene.
    ///
    /// - Parameters:
    ///   - account: The account that the window shows.
    ///   - coordinator: The onboarding coordinator.
    ///   - providers: The RPC provider coordinator.
    ///   - pasteboard: The pasteboard that copies recovery words.
    init(account: Binding<Account?>, coordinator: any OnboardingCoordinating, providers: ProvidersCoordinator,
         pasteboard: any RecoveryCopying) {
        _account = account
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
            if previous == .recovery { walletSetup.leaveBackup() }
        }
        .onChange(of: coordinator.account?.id) { showProviders() }
        .onChange(of: coordinator.finishedAccount) { _, finishedAccount in account = finishedAccount }
        .onChange(of: coordinator.savedWalletAccount) { _, saved in if let saved { account = saved } }
        .onChange(of: navigation.path.last) { showProviders() }
        .onDisappear {
            if !coordinator.isWorking, !walletImport.isPending { walletSetup.discardDraft() }
        }
        .modifier(ProvidersLifecycle(coordinator: providers))
        .alert(error: $walletSetup.error)
    }

    /// Pushes the provider choice once the wallet is saved.
    private func showProviders() {
        guard coordinator.account != nil, navigation.path.last != .providers else { return }
        navigation.path.append(.providers)
    }
}
