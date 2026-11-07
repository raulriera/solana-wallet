import Observation

/// The navigation path of onboarding and the screens that its provider choice pushes.
@MainActor
@Observable
final class OnboardingNavigation {
    /// Onboarding's own steps above welcome.
    var path: [OnboardingStep] = [] {
        didSet {
            if oldValue.contains(.importWallet), !path.contains(.importWallet) {
                walletImport.isPresented = false
            }
        }
    }
    /// Every screen above welcome, including the screens that the provider choice pushes.
    var stack: [OnboardingStep] {
        get { path + rpcCoordinator.path.map(OnboardingStep.rpcRoute) }
        set {
            let steps = newValue.filter { step in
                if case .rpcRoute = step { false } else { true }
            }
            let routes = newValue.compactMap { step -> RPCRoute? in
                if case .rpcRoute(let route) = step { route } else { nil }
            }
            if path != steps { path = steps }
            if rpcCoordinator.path != routes { rpcCoordinator.path = routes }
        }
    }
    private let walletImport: ImportWalletModel
    private let rpcCoordinator: RPCCoordinator

    /// Creates an empty navigation path.
    ///
    /// - Parameters:
    ///   - walletImport: The window's import model.
    ///   - rpcCoordinator: The window's RPC coordinator.
    init(walletImport: ImportWalletModel, rpcCoordinator: RPCCoordinator) {
        self.walletImport = walletImport
        self.rpcCoordinator = rpcCoordinator
    }

    /// Pushes phrase entry when the import can start.
    func showImport() {
        guard path.isEmpty else { return }
        walletImport.present()
        if walletImport.isPresented { path = [.importWallet] }
    }
}
