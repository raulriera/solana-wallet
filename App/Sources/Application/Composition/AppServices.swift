import Foundation
import Portfolio
import Privacy
import RPC
import Storage
import Vault
import Wallet

/// Shared production services retained by the app and supplied to its windows.
struct AppServices {
    let appearance: AppearanceServices
    let wallet: any WalletProviding
    let discovery: any AccountDiscovering
    let recovery: any RecoveryStoring
    let providerKey: any ValueStoring<String>
    let providerConnection: any ProviderConnecting<ProviderConnectionError>
    let providerRevisions = ProviderRevisions()
    let portfolios: NetworkPortfolios
    let providerSelection: any ProviderSelecting
    let customRPCConnection: any ProviderConnecting<CustomRPCError>
    let currency: CurrencySelection
    // One sampler for every window shares its remembered logo colors.
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let privateBalances: any PrivateBalancing
    let resetRevision = Revision()
    let security: SecurityServices
    /// The saved contacts and favorites, which every window shares; nothing is read until a window's Contacts loads.
    let contactStore: ContactStore
    /// The saved accounts, which every window shares; nothing is read until a window's startup loads them.
    let accountStore: AccountStore
    /// Creates new accounts in saved wallets from their recovery.
    let accountCreation: AccountCreation
    /// The sent transactions and their records, which every window shares; nothing is read or created until a window
    /// first uses a network or an account's records.
    let transactionStore: TransactionStore

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
        contactStore = ContactStore(directory: .persistentDirectory.appending(path: "Contacts",
                                                                              directoryHint: .isDirectory))
        let wallet = Wallet()
        self.wallet = wallet
        discovery = AccountDiscovery(rpc: Solana(network: .mainnet), wallet: wallet)
        recovery = KeychainStore(service: recoveryService)
        accountCreation = AccountCreation(recovery: recovery, wallet: wallet)
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
        let currencySettings = FileItem(url: .persistentDirectory.appending(path: "Currency/settings.json"),
                                        coding: .json(CurrencySettings.self))
        let rates: [CurrencySettings.RateSource: any ExchangeRateProviding] = [.europeanCentralBank: EuropeanCentralBank(),
                                                                                 .coinbase: Coinbase()]
        // Prices come in US dollars and convert to the person's currency before any portfolio values a holding.
        let prices = CurrencyPrices(prices: Jupiter(), settings: currencySettings, rates: rates)
        let portfolios = NetworkPortfolios(prices: prices) { network, prices in
            Portfolio(rpc: ProviderClient(network: network, settings: providerSettings, providerKey: providerKey),
                      prices: prices,
                      tokenListDirectory: .persistentDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
                      cacheDirectory: .ephemeralDirectory.appending(path: "Portfolio", directoryHint: .isDirectory))
        }
        self.portfolios = portfolios
        currency = CurrencySelection(settings: currencySettings, rates: rates, portfolios: { portfolios.created })
        // Approved transactions go to the selected provider and to Solana's public RPC on the same network.
        let transactionStore = TransactionStore(
            storage: TransactionStore.files(in: .persistentDirectory.appending(path: "Transactions",
                                                                               directoryHint: .isDirectory))
        ) { [recovery] network in
            let provider = ProviderClient(network: network, settings: providerSettings, providerKey: providerKey)
            return try TransactionCoordinator(rpc: provider, store: recovery, rpcs: [provider, Solana(network: network)])
        }
        self.transactionStore = transactionStore
        // Private balances keep their own client per network, apart from the portfolios' token reads.
        let privateBalances = PrivateBalances(recovery: recovery, wallet: wallet, keys: privateBalanceKeys,
                                              notes: privateBalanceNotes, codes: privateBalanceCodes) { network in
            ProviderClient(network: network, settings: providerSettings, providerKey: providerKey)
        }
        self.privateBalances = privateBalances
        let accounts = AccountStore.file(in: .persistentDirectory.appending(path: "Accounts", directoryHint: .isDirectory))
        accountStore = AccountStore(storage: accounts, cleanup: RecoveryCleanup(accounts: accounts, recovery: recovery,
                                                                                privateBalances: privateBalances))
        let providerSelection = ProviderSelection(settings: providerSettings, providerKey: providerKey,
                                                  portfolios: { portfolios.created }, revisions: providerRevisions)
        self.providerSelection = providerSelection
        customRPCConnection = CustomRPCConnection(providers: providerSelection)
        recoveryPasteboard = RecoveryPasteboard()
        security = SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: DeviceOwnerAuthentication(),
            reset: AppReset(recovery: recovery, privateBalances: privateBalances,
                            directories: directories, appearance: appearance.appearance, contacts: contactStore,
                            accounts: accountStore, transactions: transactionStore, providerKey: providerKey,
                            providerSettings: providerSettings, revision: resetRevision),
            pasteboard: recoveryPasteboard
        )
    }

    /// Creates independent root navigation for a window that starts by restoring saved wallets.
    /// - Returns: A new router whose selection is independent of other windows.
    func makeWindowRouter() -> any WindowRouting {
        WindowRouter(initialDestination: .restoringWallets)
    }

    /// Assembles startup restoration for one window from the shared accounts.
    /// - Parameter router: The owning window's navigation.
    /// - Returns: A workflow that opens saved accounts without reading recovery material.
    func makeWindowStartup(router: any WindowRouting) -> any WindowStarting {
        WindowStartup(accounts: accountStore, router: router)
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
        OnboardingCoordinator(discovery: discovery, wallet: wallet, recovery: recovery, accounts: accountStore,
                              router: router)
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
