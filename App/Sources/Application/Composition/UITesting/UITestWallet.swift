#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Saves a wallet before a UI-test launch's first screen, through onboarding's own steps.
enum UITestWallet {
    /// The launch-environment key that names the wallet to save.
    static let environmentKey = "UI_TEST_WALLET"

    /// Saves the wallet that a UI-test launch asks for.
    ///
    /// - Parameters:
    ///   - wallet: `new` to create a wallet as Create Wallet does, or recovery words to import them as Import Wallet
    ///     does.
    ///   - onboarding: The onboarding workflow that prepares and saves the wallet.
    static func prepare(_ wallet: String, with onboarding: some OnboardingCoordinating) async {
        do {
            if wallet == "new" {
                try await onboarding.create()
            } else {
                try await onboarding.importRecovery(wallet, passphrase: "")
            }
            _ = try await onboarding.complete()
        } catch {
            preconditionFailure("The UI-test wallet couldn't be prepared.")
        }
    }
}
#endif
