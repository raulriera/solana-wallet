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
    let rpcConnection: any ProviderConnecting<RPCConnectionError>
    let portfolios: PortfolioStore
    let customRPCConnection: any ProviderConnecting<CustomRPCError>
    let customPriceConnection: any ProviderConnecting<CustomPriceError>
    let artworkColors: any ArtworkColorProviding = ArtworkColors()
    let recoveryPasteboard: any RecoveryCopying
    let privateBalances: any PrivateBalancing
    let privateBalanceStore: PrivateBalanceStore
    let security: SecurityServices
    let currencyStore: CurrencyStore
    let rpcStore: RPCStore
    let priceStore: PriceStore
    let contactStore: ContactStore
    let recentPaymentStore: RecentPaymentStore
    let accountStore: AccountStore
    let accountCreation: AccountCreation
    let transactionStore: TransactionStore

    /// Creates the production services.
    init() {
        let recoveryService = "com.raulriera.widgets.recovery"
        let rpcService = "com.raulriera.widgets.rpc"
        let priceService = "com.raulriera.widgets.price"
        let privateBalanceService = "com.raulriera.widgets.private-balance"
        let directories: [URL] = [.persistentDirectory, .ephemeralDirectory]
        #if DEBUG && targetEnvironment(simulator)
        do { try UITestReset.runIfRequested(keychainServices: [recoveryService, rpcService, priceService,
                                                               privateBalanceService],
                                            directories: directories) }
        catch { preconditionFailure("The UI-test reset couldn't clear the app's saved data.") }
        #endif
        try? BackupExclusion.apply(to: .applicationSupportDirectory)
        appearance = AppearanceServices()
        contactStore = ContactStore(directory: .persistentDirectory.appending(path: "Contacts",
                                                                              directoryHint: .isDirectory))
        recentPaymentStore = RecentPaymentStore(
            directory: .persistentDirectory.appending(path: "RecentPayments", directoryHint: .isDirectory)
        )
        let wallet = Wallet()
        self.wallet = wallet
        discovery = AccountDiscovery(rpc: SolanaRPC(network: .mainnet), wallet: wallet)
        recovery = KeychainStore(service: recoveryService)
        accountCreation = AccountCreation(recovery: recovery, wallet: wallet)
        let privateBalanceKeys = KeychainItem(service: privateBalanceService, account: "keys",
                                              coding: .json(PrivateBalances.Keys.self))
        let privateBalanceNotes = KeychainItem(service: privateBalanceService, account: "notes",
                                               coding: .json(PrivateBalances.Notes.self))
        let privateBalanceCodes = KeychainItem(service: privateBalanceService, account: "codes",
                                               coding: .json(PrivateBalances.Codes.self))
        let rpcStore = RPCStore(service: rpcService)
        self.rpcStore = rpcStore
        let rpcProvider: @Sendable (Network) -> SelectedRPCProvider = { network in
            SelectedRPCProvider(network: network, rpcStore: rpcStore)
        }
        rpcConnection = HeliusConnection(rpcStore: rpcStore)
        customRPCConnection = CustomRPCConnection(rpcStore: rpcStore)
        let rates: [CurrencySettings.RateSource: any ExchangeRateProviding] = [
            .europeanCentralBank: EuropeanCentralBankExchangeRateProvider(),
            .coinbase: CoinbaseExchangeRateProvider(),
        ]
        let currencyStore = CurrencyStore(directory: .persistentDirectory.appending(path: "Currency",
                                                                                    directoryHint: .isDirectory),
                                          rates: rates)
        self.currencyStore = currencyStore
        let priceStore = PriceStore(service: priceService)
        self.priceStore = priceStore
        customPriceConnection = CustomPriceConnection(prices: priceStore)
        let prices = CurrencyPriceProvider(prices: SelectedPriceProvider(prices: priceStore), currency: currencyStore)
        let portfolios = PortfolioStore(prices: prices, currency: currencyStore, rpcStore: rpcStore,
                                        priceStore: priceStore) { network, prices in
            Portfolio(rpc: rpcProvider(network),
                      prices: prices,
                      tokenListDirectory: .persistentDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
                      cacheDirectory: .ephemeralDirectory.appending(path: "Portfolio", directoryHint: .isDirectory))
        }
        self.portfolios = portfolios
        let transactionStore = TransactionStore(
            directory: .persistentDirectory.appending(path: "Transactions", directoryHint: .isDirectory)
        ) { [recovery] network in
            try TransactionCoordinator(rpc: rpcProvider(network), store: recovery)
        }
        self.transactionStore = transactionStore
        let privateBalances = PrivateBalances(recovery: recovery, wallet: wallet, keys: privateBalanceKeys,
                                              notes: privateBalanceNotes, codes: privateBalanceCodes,
                                              client: rpcProvider)
        self.privateBalances = privateBalances
        let privateBalanceStore = PrivateBalanceStore(balances: privateBalances, transactions: transactionStore,
                                                      rpcStore: rpcStore)
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
                            stores: [contactStore, recentPaymentStore, transactionStore, currencyStore, rpcStore,
                                     priceStore, portfolios, privateBalanceStore],
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
    func makeRPCCoordinator() -> RPCCoordinator {
        RPCCoordinator(rpcStore: rpcStore, connection: rpcConnection,
                       customRPCConnection: customRPCConnection)
    }

    /// Creates a Prices coordinator.
    ///
    /// - Returns: A new Prices coordinator.
    func makePricesCoordinator() -> PricesCoordinator {
        PricesCoordinator(prices: priceStore, connection: customPriceConnection)
    }

    /// Creates an appearance settings model.
    ///
    /// - Returns: A new appearance settings model.
    func makeAppearanceSettingsModel() -> AppearanceSettingsModel {
        AppearanceSettingsModel(appearance: appearance.appearance, catalog: appearance.catalog, packages: appearance.packages)
    }
}
