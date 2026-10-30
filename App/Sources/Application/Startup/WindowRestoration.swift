import RPC
import SwiftUI

/// Restores a window's wallet after the system ends the app, and remembers the account the window shows.
///
/// The window keeps only the identities of its account and wallet; startup still resolves them against saved accounts.
/// A window whose account another window deletes keeps the account it shows instead. Entering onboarding forgets the
/// account and starts the next wallet on Mainnet and its portfolio, also in a window that finds no saved wallet after
/// another window reset the app.
private struct WindowRestoration: ViewModifier {
    @SceneStorage("window.accountID") private var accountID: String?
    @SceneStorage("window.walletID") private var walletID: String?
    /// The network that the window shows, kept with its scene state.
    @Binding var network: Network
    /// The section that the window shows, kept with its scene state.
    @Binding var section: WalletSection
    let window: WindowModel
    let attempt: Int

    /// Runs startup with the restored identities and records later account changes.
    /// - Parameter content: The window's root destinations.
    /// - Returns: Content whose startup prefers the account this window showed last.
    func body(content: Content) -> some View {
        content
            .task(id: attempt) { await window.restore(preferring: restoredSelection) }
            .onChange(of: window.destination) { _, destination in remember(destination) }
    }

    /// The account and wallet that the window showed before the system ended the app, while both identities read.
    private var restoredSelection: WindowModel.Selection? {
        guard let accountID = accountID.flatMap(UUID.init(uuidString:)),
              let walletID = walletID.flatMap(UUID.init(uuidString:)) else { return nil }
        return WindowModel.Selection(accountID: accountID, walletID: walletID)
    }

    /// Chooses and records the shown account, and starts the next wallet over on onboarding; pending and failed reads
    /// keep the identities for the next attempt.
    /// - Parameter destination: The window's new root destination.
    private func remember(_ destination: WindowDestination) {
        switch destination {
        case .wallet(let account):
            // A window whose account another window deletes chooses the account that it shows instead.
            window.account = account
            accountID = account.id.uuidString
            walletID = account.recoveryID.uuidString
        case .onboarding:
            // The wallet that another window saves next doesn't open in this window.
            window.account = nil
            accountID = nil
            walletID = nil
            network = .mainnet
            section = .portfolio
        case .restoringWallets, .walletRestorationFailed:
            break
        }
    }
}

extension View {
    /// Restores a window's wallet once at its root and remembers the account it shows.
    /// - Parameters:
    ///   - window: The window's navigation, whose shown accounts are remembered.
    ///   - attempt: Changes to run startup again after a failed read.
    ///   - network: The network that the window shows, which returns to Mainnet on onboarding.
    ///   - section: The section that the window shows, which returns to the portfolio on onboarding.
    /// - Returns: A view whose window reopens the account it showed when the system ended the app.
    func windowRestoration(_ window: WindowModel, attempt: Int, network: Binding<Network>,
                           section: Binding<WalletSection>) -> some View {
        modifier(WindowRestoration(network: network, section: section, window: window, attempt: attempt))
    }
}
