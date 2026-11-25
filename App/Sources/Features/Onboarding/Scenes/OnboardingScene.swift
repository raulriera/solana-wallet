import SwiftUI
import Vault

/// Shows onboarding's steps, from welcome to the RPC provider choice.
struct OnboardingScene: View {
    @State private var navigation: OnboardingNavigation
    @State private var walletImport: ImportWalletModel
    @State private var walletSetup: WalletSetupModel
    @State private var coordinator: any OnboardingCoordinating
    @State private var rpcCoordinator: RPCCoordinator
    @Binding var account: Account?
    let pasteboard: any RecoveryCopying

    /// Creates an onboarding scene.
    ///
    /// - Parameters:
    ///   - account: The account that the window shows.
    ///   - coordinator: The onboarding coordinator.
    ///   - rpcCoordinator: The RPC provider coordinator.
    ///   - pasteboard: The pasteboard that copies recovery words.
    init(account: Binding<Account?>, coordinator: any OnboardingCoordinating, rpcCoordinator: RPCCoordinator,
         pasteboard: any RecoveryCopying) {
        _account = account
        self.coordinator = coordinator
        self.rpcCoordinator = rpcCoordinator
        self.pasteboard = pasteboard
        let walletImport = ImportWalletModel(coordinator: coordinator)
        self.walletImport = walletImport
        walletSetup = WalletSetupModel(coordinator: coordinator, rpcCoordinator: rpcCoordinator)
        navigation = OnboardingNavigation(walletImport: walletImport, rpcCoordinator: rpcCoordinator)
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
                                    .importLifecycle(presentationID: presentationID)
                                    .id(presentationID)
                            }
                        case .rpc:
                            RPCChoiceScreen(coordinator: rpcCoordinator, continueSetup: walletSetup.open)
                                .navigationBarBackButtonHidden()
                        case .rpcRoute(let route):
                            RPCDestination(coordinator: rpcCoordinator, route: route)
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
        .onChange(of: coordinator.account?.id) { showRPC() }
        .onChange(of: coordinator.finishedAccount) { _, finishedAccount in account = finishedAccount }
        .onChange(of: coordinator.savedWalletAccount) { _, saved in if let saved { account = saved } }
        .onChange(of: navigation.path.last) { showRPC() }
        .onDisappear {
            if !coordinator.isWorking, !walletImport.isPending { walletSetup.discardDraft() }
        }
        .modifier(RPCLifecycle(coordinator: rpcCoordinator))
        .alert(error: $walletSetup.error)
    }

    /// Pushes the provider choice once the wallet is saved.
    private func showRPC() {
        guard coordinator.account != nil, navigation.path.last != .rpc else { return }
        navigation.path.append(.rpc)
    }
}
