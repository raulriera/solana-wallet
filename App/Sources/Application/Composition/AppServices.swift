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
    let providerConnection: any ProviderConnecting<ProviderConnectionError>
    let portfolios: PortfolioStore
    let customRPCConnection: any ProviderConnecting<CustomRPCError>
    // One sampler for every window shares its remembered logo colors.
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let privateBalances: any PrivateBalancing
    /// Each account's private balance on each network, which every window shares; nothing is read until a window
    /// observes an account.
    let privateBalanceStore: PrivateBalanceStore
    let resetRevision = Revision()
    let security: SecurityServices
    /// The currency and rate source choice, which every window shares; nothing is read until a window's Currency or a
    /// price lookup reads it.
    let currencyStore: CurrencyStore
    /// The RPC provider choice, custom RPCs, and Helius's key, which every window shares; each window reads them when
    /// it appears.
    let providerStore: ProviderStore
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
        let providerStore = ProviderStore(service: providerService)
        self.providerStore = providerStore
        providerConnection = HeliusConnection(providers: providerStore)
        customRPCConnection = CustomRPCConnection(providers: providerStore)
        let rates: [CurrencySettings.RateSource: any ExchangeRateProviding] = [.europeanCentralBank: EuropeanCentralBank(),
                                                                                 .coinbase: Coinbase()]
        let currencyStore = CurrencyStore(directory: .persistentDirectory.appending(path: "Currency",
                                                                                    directoryHint: .isDirectory),
                                          rates: rates)
        self.currencyStore = currencyStore
        // Prices come in US dollars and convert to the person's currency before any portfolio values a holding.
        let prices = CurrencyPrices(prices: Jupiter(), currency: currencyStore)
        let portfolios = PortfolioStore(prices: prices, currency: currencyStore,
                                        providers: providerStore) { network, prices in
            Portfolio(rpc: ProviderClient(network: network, providers: providerStore),
                      prices: prices,
                      tokenListDirectory: .persistentDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
                      cacheDirectory: .ephemeralDirectory.appending(path: "Portfolio", directoryHint: .isDirectory))
        }
        self.portfolios = portfolios
        // Approved transactions go to the selected provider and to Solana's public RPC on the same network.
        let transactionStore = TransactionStore(
            directory: .persistentDirectory.appending(path: "Transactions", directoryHint: .isDirectory)
        ) { [recovery] network in
            let provider = ProviderClient(network: network, providers: providerStore)
            return try TransactionCoordinator(rpc: provider, store: recovery, rpcs: [provider, Solana(network: network)])
        }
        self.transactionStore = transactionStore
        // Private balances keep their own client per network, apart from the portfolios' token reads.
        let privateBalances = PrivateBalances(recovery: recovery, wallet: wallet, keys: privateBalanceKeys,
                                              notes: privateBalanceNotes, codes: privateBalanceCodes) { network in
            ProviderClient(network: network, providers: providerStore)
        }
        self.privateBalances = privateBalances
        let privateBalanceStore = PrivateBalanceStore(balances: privateBalances, transactions: transactionStore,
                                                      providers: providerStore)
        self.privateBalanceStore = privateBalanceStore
        let accounts = AccountStore.file(in: .persistentDirectory.appending(path: "Accounts", directoryHint: .isDirectory))
        accountStore = AccountStore(storage: accounts, cleanup: RecoveryCleanup(accounts: accounts, recovery: recovery,
                                                                                privateBalances: privateBalances))
        recoveryPasteboard = RecoveryPasteboard()
        security = SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: DeviceOwnerAuthentication(),
            reset: AppReset(recovery: recovery, privateBalances: privateBalances,
                            directories: directories, appearance: appearance.appearance,
                            stores: [contactStore, accountStore, transactionStore, currencyStore, providerStore,
                                     portfolios, privateBalanceStore],
                            revision: resetRevision),
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
        ProvidersCoordinator(providers: providerStore, connection: providerConnection,
                             customRPCConnection: customRPCConnection)
    }

    /// Assembles a preference-editing workflow around the app's shared appearance services.
    /// - Returns: Independent operation and presentation state for the owning window.
    func makeAppearanceSettingsModel() -> AppearanceSettingsModel {
        AppearanceSettingsModel(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
