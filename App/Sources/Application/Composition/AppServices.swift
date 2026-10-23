import Foundation
import Portfolio
import Privacy
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
    let providerKey: any ValueStoring<String>
    let providerConnection: any ProviderConnecting<ProviderConnectionError>
    let providerRevisions = ProviderRevisions()
    let portfolios: NetworkPortfolios
    let transactions: NetworkTransactions
    let providerSelection: any ProviderSelecting
    let customRPCConnection: any ProviderConnecting<CustomRPCError>
    // One sampler for every window shares its remembered logo colors.
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let recoveryCleanup: any RecoveryCleaning
    let privateBalances: any PrivateBalancing
    let resetRevision = Revision()
    let security: SecurityServices

    /// Creates production services after any explicit simulator UI-test reset.
    init() {
        let recoveryService = "com.raulriera.widgets.recovery"
        let providerService = "com.raulriera.widgets.provider"
        let privateBalanceService = "com.raulriera.widgets.private-balance"
        let directories: [URL] = [.persistentDirectory, .ephemeralDirectory]
        #if DEBUG && targetEnvironment(simulator)
        // A UI test must not run against saved data that it couldn't clear.
        do { try UITestReset.runIfRequested(keychainServices: [recoveryService, providerService, privateBalanceService],
                                            directories: directories) }
        catch { preconditionFailure("The UI-test reset couldn't clear the app's saved data.") }
        #endif
        // Exclusion is guidance to the system; a failure must not block the app, and the next launch tries again.
        try? BackupExclusion.apply(to: .applicationSupportDirectory)
        appearance = AppearanceServices()
        let wallet = Wallet()
        self.wallet = wallet
        discovery = AccountDiscovery(rpc: Solana(network: .mainnet), wallet: wallet)
        recovery = KeychainStore(service: recoveryService)
        accounts = AccountStore()
        let privateBalanceKeys = KeychainItem(service: privateBalanceService, account: "keys",
                                              coding: .json(PrivateBalances.Keys.self))
        let privateBalanceNotes = KeychainItem(service: privateBalanceService, account: "notes",
                                               coding: .json(PrivateBalances.Notes.self))
        let privateBalanceCodes = KeychainItem(service: privateBalanceService, account: "codes",
                                               coding: .json(PrivateBalances.Codes.self))
        let providerKey = KeychainItem(service: providerService, account: "api-key", coding: .utf8)
        let providerSettings = KeychainItem(service: providerService, account: "settings", coding: .json(ProviderSettings.self))
        self.providerKey = providerKey
        providerConnection = HeliusConnection(providerKey: providerKey, revisions: providerRevisions)
        let portfolios = NetworkPortfolios(prices: Jupiter()) { network, prices in
            Portfolio(rpc: ProviderClient(network: network, settings: providerSettings, providerKey: providerKey),
                      prices: prices,
                      tokenListDirectory: .persistentDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
                      cacheDirectory: .ephemeralDirectory.appending(path: "Portfolio", directoryHint: .isDirectory))
        }
        self.portfolios = portfolios
        // Approved transactions go to the selected provider and to Solana's public RPC on the same network.
        transactions = NetworkTransactions { [recovery] network in
            let provider = ProviderClient(network: network, settings: providerSettings, providerKey: providerKey)
            return try TransactionCoordinator(rpc: provider, store: recovery, rpcs: [provider, Solana(network: network)])
        }
        // Private balances keep their own client per network, apart from the portfolios' token reads.
        let privateBalances = PrivateBalances(recovery: recovery, wallet: wallet, keys: privateBalanceKeys,
                                              notes: privateBalanceNotes, codes: privateBalanceCodes) { network in
            ProviderClient(network: network, settings: providerSettings, providerKey: providerKey)
        }
        self.privateBalances = privateBalances
        recoveryCleanup = RecoveryCleanup(accounts: accounts, recovery: recovery, privateBalances: privateBalances)
        let providerSelection = ProviderSelection(settings: providerSettings, providerKey: providerKey,
                                                  portfolios: { portfolios.created }, revisions: providerRevisions)
        self.providerSelection = providerSelection
        customRPCConnection = CustomRPCConnection(providers: providerSelection)
        recoveryPasteboard = RecoveryPasteboard()
        security = SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: DeviceOwnerAuthentication(),
            reset: AppReset(recovery: recovery, privateBalances: privateBalances,
                            directories: directories, appearance: appearance.appearance,
                            providerKey: providerKey, providerSettings: providerSettings, revision: resetRevision),
            pasteboard: recoveryPasteboard
        )
    }

    /// Creates independent root navigation for a window that starts by restoring saved wallets.
    /// - Returns: A new router whose selection is independent of other windows.
    func makeWindowRouter() -> any WindowRouting {
        WindowRouter(initialDestination: .restoringWallets)
    }

    /// Assembles startup restoration for one window behind the shared launch cleanup.
    /// - Parameter router: The owning window's navigation.
    /// - Returns: A workflow that opens saved accounts without reading recovery material.
    func makeWindowStartup(router: any WindowRouting) -> any WindowStarting {
        WindowStartup(accounts: accounts, cleanup: recoveryCleanup, router: router)
    }

    /// Creates independent portfolio presentation around a network's shared portfolio service.
    /// - Parameter network: The network that the window shows. Mainnet's service exists from launch; another
    ///   network's service is created when a window first shows that network.
    /// - Returns: A coordinator for that network, whose observation and refreshes belong to one window.
    func makePortfolioCoordinator(for network: Network) -> any PortfolioCoordinating {
        portfolios.makeCoordinator(for: network)
    }

    /// Assembles a fresh onboarding workflow around the app's shared services.
    /// - Parameter router: The owning window's root navigation.
    /// - Returns: Independent draft state for the window that retains this coordinator.
    func makeOnboardingCoordinator(router: any WindowRouting) -> any OnboardingCoordinating {
        OnboardingCoordinator(discovery: discovery, wallet: wallet, recovery: recovery, accounts: accounts, router: router)
    }

    /// Creates independent Security & Privacy navigation and steps around the shared security services.
    /// - Returns: A coordinator whose path and steps belong to one window.
    func makeSecurityCoordinator() -> SecurityCoordinator {
        SecurityCoordinator(services: security)
    }

    /// Creates independent RPC provider choices, pushed screens, and key entry around the shared provider services.
    /// - Returns: A coordinator whose choices, pushed screens, and key entry belong to one window.
    func makeProvidersCoordinator() -> ProvidersCoordinator {
        ProvidersCoordinator(providers: providerSelection, providerKey: providerKey, connection: providerConnection,
                             customRPCConnection: customRPCConnection, revisions: providerRevisions)
    }

    /// Assembles a preference-editing workflow around the app's shared appearance services.
    /// - Returns: Independent operation and presentation state for the owning window.
    func makeAppearanceSettingsModel() -> AppearanceSettingsModel {
        AppearanceSettingsModel(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
