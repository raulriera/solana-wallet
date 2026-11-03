import Foundation
import Portfolio
import Privacy
import RPC
import Storage
import Vault
import Wallet

/// The production services that the app's windows share.
struct AppServices {
    let appearance: AppearanceServices
    let wallet: any WalletProviding
    let discovery: any AccountDiscovering
    let recovery: any RecoveryStoring
    let providerConnection: any ProviderConnecting<ProviderConnectionError>
    let portfolios: PortfolioStore
    let customRPCConnection: any ProviderConnecting<CustomRPCError>
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let privateBalances: any PrivateBalancing
    let privateBalanceStore: PrivateBalanceStore
    let security: SecurityServices
    let currencyStore: CurrencyStore
    let providerStore: ProviderStore
    let contactStore: ContactStore
    let accountStore: AccountStore
    let accountCreation: AccountCreation
    let transactionStore: TransactionStore

    /// Creates the production services.
    init() {
        let recoveryService = "com.raulriera.widgets.recovery"
        let providerService = "com.raulriera.widgets.provider"
        let privateBalanceService = "com.raulriera.widgets.private-balance"
        let directories: [URL] = [.persistentDirectory, .ephemeralDirectory]
        #if DEBUG && targetEnvironment(simulator)
        do { try UITestReset.runIfRequested(keychainServices: [recoveryService, providerService, privateBalanceService],
                                            directories: directories) }
        catch { preconditionFailure("The UI-test reset couldn't clear the app's saved data.") }
        #endif
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
        let mainnetRings = Zolana(network: .mainnet)
        let devnetRings = Zolana(network: .devnet)
        let providerClient: @Sendable (Network) -> ProviderClient = { network in
            let rings = switch network {
            case .mainnet: mainnetRings
            case .devnet: devnetRings
            }
            return ProviderClient(network: network, providers: providerStore, rings: rings)
        }
        providerConnection = HeliusConnection(providers: providerStore)
        customRPCConnection = CustomRPCConnection(providers: providerStore)
        let rates: [CurrencySettings.RateSource: any ExchangeRateProviding] = [.europeanCentralBank: EuropeanCentralBank(),
                                                                                 .coinbase: Coinbase()]
        let currencyStore = CurrencyStore(directory: .persistentDirectory.appending(path: "Currency",
                                                                                    directoryHint: .isDirectory),
                                          rates: rates)
        self.currencyStore = currencyStore
        let prices = CurrencyPrices(prices: Jupiter(), currency: currencyStore)
        let portfolios = PortfolioStore(prices: prices, currency: currencyStore,
                                        providers: providerStore) { network, prices in
            Portfolio(rpc: providerClient(network),
                      prices: prices,
                      tokenListDirectory: .persistentDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
                      cacheDirectory: .ephemeralDirectory.appending(path: "Portfolio", directoryHint: .isDirectory))
        }
        self.portfolios = portfolios
        let transactionStore = TransactionStore(
            directory: .persistentDirectory.appending(path: "Transactions", directoryHint: .isDirectory)
        ) { [recovery] network in
            let provider = providerClient(network)
            return try TransactionCoordinator(rpc: provider, store: recovery, rpcs: [provider, Solana(network: network)])
        }
        self.transactionStore = transactionStore
        let privateBalances = PrivateBalances(recovery: recovery, wallet: wallet, keys: privateBalanceKeys,
                                              notes: privateBalanceNotes, codes: privateBalanceCodes,
                                              client: providerClient)
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
                            stores: [contactStore, transactionStore, currencyStore, providerStore, portfolios,
                                     privateBalanceStore],
                            accounts: accountStore),
            pasteboard: recoveryPasteboard
        )
    }

    /// Creates an onboarding coordinator.
    ///
    /// - Returns: A new onboarding coordinator.
    func makeOnboardingCoordinator() -> any OnboardingCoordinating {
        OnboardingCoordinator(discovery: discovery, wallet: wallet, recovery: recovery, accounts: accountStore)
    }

    /// Creates a Security & Privacy coordinator.
    ///
    /// - Returns: A new Security & Privacy coordinator.
    func makeSecurityCoordinator() -> SecurityCoordinator {
        SecurityCoordinator(services: security)
    }

    /// Creates an RPC provider coordinator.
    ///
    /// - Returns: A new RPC provider coordinator.
    func makeProvidersCoordinator() -> ProvidersCoordinator {
        ProvidersCoordinator(providers: providerStore, connection: providerConnection,
                             customRPCConnection: customRPCConnection)
    }

    /// Creates an appearance settings model.
    ///
    /// - Returns: A new appearance settings model.
    func makeAppearanceSettingsModel() -> AppearanceSettingsModel {
        AppearanceSettingsModel(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
