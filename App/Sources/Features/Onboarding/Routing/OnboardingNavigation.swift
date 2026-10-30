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
        get { path + providers.path.map(OnboardingStep.providersRoute) }
        set {
            let steps = newValue.filter { step in
                if case .providersRoute = step { false } else { true }
            }
            let routes = newValue.compactMap { step -> ProvidersRoute? in
                if case .providersRoute(let route) = step { route } else { nil }
            }
            if path != steps { path = steps }
            if providers.path != routes { providers.path = routes }
        }
    }
    private let walletImport: ImportWalletModel
    private let providers: ProvidersCoordinator

    /// Creates an empty navigation path.
    ///
    /// - Parameters:
    ///   - walletImport: The window's import model.
    ///   - providers: The window's provider coordinator.
    init(walletImport: ImportWalletModel, providers: ProvidersCoordinator) {
        self.walletImport = walletImport
        self.providers = providers
    }

    /// Pushes phrase entry when the import can start.
    func showImport() {
        guard path.isEmpty else { return }
        walletImport.present()
        if walletImport.isPresented { path = [.importWallet] }
    }
}
