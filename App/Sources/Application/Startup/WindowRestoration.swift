import RPC
import SwiftUI

/// Restores a window's wallet and remembers the account the window shows.
private struct WindowRestoration: ViewModifier {
    @SceneStorage("window.accountID") private var accountID: String?
    @SceneStorage("window.walletID") private var walletID: String?
    @Binding var network: Network
    @Binding var section: WalletSection
    let window: WindowModel
    let attempt: Int

    func body(content: Content) -> some View {
        content
            .task(id: attempt) { await window.restore(preferring: restoredSelection) }
            .onChange(of: window.destination) { _, destination in remember(destination) }
    }

    private var restoredSelection: WindowModel.Selection? {
        guard let accountID = accountID.flatMap(UUID.init(uuidString:)),
              let walletID = walletID.flatMap(UUID.init(uuidString:)) else { return nil }
        return WindowModel.Selection(accountID: accountID, walletID: walletID)
    }

    /// Records the shown account, and resets the window's account, network, and section on onboarding.
    ///
    /// - Parameter destination: The window's new root destination.
    private func remember(_ destination: WindowDestination) {
        switch destination {
        case .wallet(let account):
            window.account = account
            accountID = account.id.uuidString
            walletID = account.recoveryID.uuidString
        case .onboarding:
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
    /// Restores a window's wallet and remembers the account the window shows.
    ///
    /// - Parameters:
    ///   - window: The window's navigation.
    ///   - attempt: A value whose change runs startup again.
    ///   - network: The network that the window shows.
    ///   - section: The section that the window shows.
    /// - Returns: A view that restores the window's wallet.
    func windowRestoration(_ window: WindowModel, attempt: Int, network: Binding<Network>,
                           section: Binding<WalletSection>) -> some View {
        modifier(WindowRestoration(network: network, section: section, window: window, attempt: attempt))
    }
}
