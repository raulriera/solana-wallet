import Observation

/// Owns onboarding's navigation path, ends an import as soon as its step leaves the path, and shows the screens that the
/// provider choice pushes above it.
@MainActor
@Observable
final class OnboardingNavigation {
    /// Onboarding's own steps above welcome, in order; Back removes the last one.
    var path: [OnboardingStep] = [] {
        didSet {
            // Back must invalidate an in-flight import before SwiftUI delivers task cancellation.
            if oldValue.contains(.importWallet), !path.contains(.importWallet) {
                importSubmission.isPresented = false
            }
        }
    }
    /// Every screen above welcome: onboarding's own steps, then the screens that the provider choice pushed.
    ///
    /// The provider choice keeps its pushed screens in its own path, as it does in Settings, so Back from one of them
    /// changes that path and leaves onboarding's own steps as they are.
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
    private let importSubmission: ImportSubmission
    private let providers: ProvidersCoordinator

    /// Creates an empty path that keeps the window's import presentation and provider screens in step with navigation.
    /// - Parameters:
    ///   - importSubmission: The window's import attempts, ended when phrase entry leaves the path.
    ///   - providers: The window's provider choice, whose pushed screens show above onboarding's steps.
    init(importSubmission: ImportSubmission, providers: ProvidersCoordinator) {
        self.importSubmission = importSubmission
        self.providers = providers
    }

    /// Pushes phrase entry once the import submission accepts a new presentation.
    func showImport() {
        guard path.isEmpty else { return }
        importSubmission.present()
        if importSubmission.isPresented { path = [.importWallet] }
    }
}
