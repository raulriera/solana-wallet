import Observation

/// Owns one window's navigation, which the window creates when it first appears; the services stay shared.
@MainActor
@Observable
final class WindowModel {
    /// The window's root navigation.
    let router: any WindowRouting
    /// Restores the window's wallet when the window opens.
    let startup: any WindowStarting

    /// The account that the window shows, or `nil` while it shows no wallet.
    ///
    /// Setting another account shows it in this window only, and the window reopens it after the system ends the app.
    /// Setting `nil` changes nothing; only startup and a reset leave the wallet.
    var account: Account? {
        get {
            guard case .wallet(let account) = router.destination else { return nil }
            return account
        }
        set {
            guard let newValue else { return }
            router.route(to: .wallet(newValue))
        }
    }

    /// Creates the window's navigation around the shared services.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        let router = services.makeWindowRouter()
        self.router = router
        startup = services.makeWindowStartup(router: router)
    }
}
