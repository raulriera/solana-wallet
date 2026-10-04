import RPC
import Vault
import Wallet

/// Shared production services retained by the app and supplied to its windows.
struct AppServices {
    let appearance: AppearanceServices
    let wallet: any WalletProviding
    let discovery: any AccountDiscovering
    let recovery: any RecoveryStoring
    let accounts: any AccountStoring

    /// Creates production services after any explicit simulator UI-test reset.
    /// - Throws: An error if the bundled appearance or a storage configuration is invalid.
    init() throws {
        let recoveryService = "com.raulriera.widgets.recovery"
        #if DEBUG && targetEnvironment(simulator)
        try UITestReset.runIfRequested(recoveryService: recoveryService)
        #endif
        appearance = try AppearanceServices()
        wallet = Wallet()
        discovery = AccountDiscovery(rpc: Solana(network: .mainnet), wallet: wallet)
        recovery = KeychainStore(service: recoveryService)
        accounts = try AccountStore()
    }

    /// Creates independent root navigation for a window.
    /// - Parameter initialDestination: The destination chosen by the caller for this window.
    /// - Returns: A new router whose selection is independent of other windows.
    func makeWindowRouter(initialDestination: WindowDestination) -> any WindowRouting {
        WindowRouter(initialDestination: initialDestination)
    }

    /// Assembles read-only startup restoration for one window.
    /// - Parameter router: The owning window's navigation.
    /// - Returns: A workflow that opens saved accounts without accessing recovery material.
    func makeWindowStartup(router: any WindowRouting) -> any WindowStarting {
        WindowStartup(accounts: accounts, router: router)
    }

    /// Assembles a fresh onboarding workflow around the app's shared services.
    /// - Parameter router: The owning window's root navigation.
    /// - Returns: Independent draft state for the window that retains this coordinator.
    func makeOnboardingCoordinator(router: any WindowRouting) -> any OnboardingCoordinating {
        OnboardingCoordinator(discovery: discovery, wallet: wallet, recovery: recovery, accounts: accounts, router: router)
    }

    /// Assembles a preference-editing workflow around the app's shared appearance services.
    /// - Returns: Independent operation and presentation state for the owning settings scene.
    func makeAppearanceSettings() -> AppearanceSettings {
        AppearanceSettings(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
