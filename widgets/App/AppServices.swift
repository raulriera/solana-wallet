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
}
