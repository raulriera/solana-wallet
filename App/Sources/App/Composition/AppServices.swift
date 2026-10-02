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

    /// Creates independent root navigation for a window.
    /// - Parameter initialDestination: The destination chosen by the caller for this window.
    /// - Returns: A new router whose selection is independent of other windows.
    func makeWindowRouter(initialDestination: WindowDestination) -> any WindowRouting {
        WindowRouter(initialDestination: initialDestination)
    }

    /// Assembles a fresh onboarding workflow around the app's shared services.
    /// - Parameter router: The owning window's root navigation.
    /// - Returns: Independent draft state for the window that retains this coordinator.
    func makeOnboardingCoordinator(router: any WindowRouting) -> any OnboardingCoordinating {
        OnboardingCoordinator(wallet: wallet, recovery: recovery, accounts: accounts, router: router)
    }

    /// Assembles a preference-editing workflow around the app's shared appearance services.
    /// - Returns: Independent operation and presentation state for the owning settings scene.
    func makeAppearanceSettings() -> AppearanceSettings {
        AppearanceSettings(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
