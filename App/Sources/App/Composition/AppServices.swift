import Vault
import Wallet

/// Shared production services retained by the app and supplied to its windows.
struct AppServices {
    let appearance: AppearanceServices
    let wallet: any WalletProviding
    let recovery: any RecoveryStoring
    let accounts: any AccountStoring

    /// Creates shared services without generating or accessing wallet recovery material.
    /// - Throws: An error if the bundled appearance or a storage configuration is invalid.
    init() throws {
        appearance = try AppearanceServices()
        wallet = Wallet()
        recovery = KeychainStore(service: "com.raulriera.widgets.recovery")
        accounts = try AccountStore()
    }

    /// Assembles a fresh onboarding workflow around the app's shared services.
    /// - Returns: Independent draft state for the window that retains this coordinator.
    func makeOnboardingCoordinator() -> any OnboardingCoordinating {
        OnboardingCoordinator(wallet: wallet, recovery: recovery, accounts: accounts)
    }
}
