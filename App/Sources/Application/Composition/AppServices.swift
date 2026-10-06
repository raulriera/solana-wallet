import Foundation
import Portfolio
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
    let providerConnection: any ProviderConnecting
    let providerKeyRevision = ProviderKeyRevision()
    let portfolio: any PortfolioProviding
    // One sampler for every window shares its remembered logo colors.
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let recoveryCleanup: any RecoveryCleaning
    let resetRevision = AppResetRevision()
    let security: SecurityServices

    /// Creates production services after any explicit simulator UI-test reset.
    /// - Throws: An error if the bundled appearance or a storage configuration is invalid.
    init() throws {
        let recoveryService = "com.raulriera.widgets.recovery"
        let providerService = "com.raulriera.widgets.provider"
        #if DEBUG && targetEnvironment(simulator)
        try UITestReset.runIfRequested(keychainServices: [recoveryService, providerService])
        #endif
        // Exclusion is guidance to the system; a failure must not block the app, and the next launch tries again.
        try? BackupExclusion.apply(to: .applicationSupportDirectory)
        appearance = try AppearanceServices()
        wallet = Wallet()
        discovery = AccountDiscovery(rpc: Solana(network: .mainnet), wallet: wallet)
        recovery = KeychainStore(service: recoveryService)
        accounts = try AccountStore()
        recoveryCleanup = RecoveryCleanup(accounts: accounts, recovery: recovery)
        let providerKeys = ProviderKeyStore(service: providerService)
        providerConnection = HeliusConnection(keys: providerKeys)
        // One service for every window shares its cache, subscriptions, and price pacing.
        portfolio = Portfolio(rpc: HeliusClient(keys: providerKeys), prices: Jupiter())
        recoveryPasteboard = RecoveryPasteboard()
        security = SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: DeviceOwnerAuthentication(),
            reset: AppReset(recovery: recovery, accounts: accounts, providerKeys: providerKeys, revision: resetRevision),
            pasteboard: recoveryPasteboard
        )
    }

    /// Creates independent root navigation for a window.
    /// - Parameter initialDestination: The destination chosen by the caller for this window.
    /// - Returns: A new router whose selection is independent of other windows.
    func makeWindowRouter(initialDestination: WindowDestination) -> any WindowRouting {
        WindowRouter(initialDestination: initialDestination)
    }

    /// Assembles startup restoration for one window behind the shared launch cleanup.
    /// - Parameter router: The owning window's navigation.
    /// - Returns: A workflow that opens saved accounts without reading recovery material.
    func makeWindowStartup(router: any WindowRouting) -> any WindowStarting {
        WindowStartup(accounts: accounts, cleanup: recoveryCleanup, router: router)
    }

    /// Creates independent portfolio presentation around the shared portfolio service.
    /// - Returns: A coordinator whose observation and refreshes belong to one window.
    func makePortfolioCoordinator() -> any PortfolioCoordinating {
        PortfolioCoordinator(service: portfolio)
    }

    /// Assembles a fresh onboarding workflow around the app's shared services.
    /// - Parameter router: The owning window's root navigation.
    /// - Returns: Independent draft state for the window that retains this coordinator.
    func makeOnboardingCoordinator(router: any WindowRouting) -> any OnboardingCoordinating {
        OnboardingCoordinator(discovery: discovery, wallet: wallet, recovery: recovery, accounts: accounts, router: router)
    }

    /// Creates independent Security & Privacy navigation and steps around the shared security services.
    /// - Returns: A flow whose path and steps belong to one window.
    func makeSecurityFlow() -> SecurityFlow {
        SecurityFlow(services: security)
    }

    /// Assembles a preference-editing workflow around the app's shared appearance services.
    /// - Returns: Independent operation and presentation state for the owning window.
    func makeAppearanceSettings() -> AppearanceSettings {
        AppearanceSettings(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
