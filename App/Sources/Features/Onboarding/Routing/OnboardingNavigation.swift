import Observation

/// Owns onboarding's navigation path and ends an import as soon as its step leaves the path.
@MainActor
@Observable
final class OnboardingNavigation {
    /// The steps pushed above welcome, in order; Back removes the last one.
    var path: [OnboardingStep] = [] {
        didSet {
            // Back must invalidate an in-flight import before SwiftUI delivers task cancellation.
            if oldValue.contains(.importWallet), !path.contains(.importWallet) {
                importSubmission.isPresented = false
            }
        }
    }
    private let importSubmission: ImportSubmission

    /// Creates an empty path that keeps the window's import presentation in step with navigation.
    /// - Parameter importSubmission: The window's import attempts, ended when phrase entry leaves the path.
    init(importSubmission: ImportSubmission) {
        self.importSubmission = importSubmission
    }

    /// Pushes phrase entry once the import submission accepts a new presentation.
    func showImport() {
        guard path.isEmpty else { return }
        importSubmission.present()
        if importSubmission.isPresented { path = [.importWallet] }
    }
}
