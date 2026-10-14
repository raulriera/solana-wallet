import RPC
import SwiftUI

/// Restores a window's wallet after the system ends the app, and remembers the wallet the window shows.
///
/// The window keeps only the account's public identifier; startup still resolves it against saved accounts. Entering
/// onboarding forgets the wallet and starts the next one on Mainnet and its portfolio, also in a window that reconnects
/// to find no saved wallet after another window reset the app.
private struct WindowRestoration: ViewModifier {
    @SceneStorage("window.accountID") private var accountID: String?
    /// The network that the window shows, kept with its scene state.
    @Binding var network: Network
    /// The section that the window shows, kept with its scene state.
    @Binding var section: WalletSection
    let startup: any WindowStarting
    let router: any WindowRouting
    let attempt: Int

    /// Runs startup with the restored identifier and records later wallet changes.
    /// - Parameter content: The window's root destinations.
    /// - Returns: Content whose startup prefers the wallet this window showed last.
    func body(content: Content) -> some View {
        content
            .task(id: attempt) { await startup.restore(preferring: accountID.flatMap(UUID.init(uuidString:))) }
            .onChange(of: router.destination) { _, destination in remember(destination) }
    }

    /// Records the shown wallet, and starts the next wallet over on onboarding; pending and failed reads keep the
    /// identifier for the next attempt.
    /// - Parameter destination: The window's new root destination.
    private func remember(_ destination: WindowDestination) {
        switch destination {
        case .wallet(let account):
            accountID = account.id.uuidString
        case .onboarding:
            accountID = nil
            network = .mainnet
            section = .portfolio
        case .restoringWallets, .walletRestorationFailed:
            break
        }
    }
}

extension View {
    /// Restores a window's wallet once at its root and remembers the wallet it shows.
    /// - Parameters:
    ///   - startup: The window's read-only startup workflow.
    ///   - router: The window's navigation, whose wallet destinations are remembered.
    ///   - attempt: Changes to run startup again after a failed read.
    ///   - network: The network that the window shows, which returns to Mainnet on onboarding.
    ///   - section: The section that the window shows, which returns to the portfolio on onboarding.
    /// - Returns: A view whose window reopens the wallet it showed when the system ended the app.
    func windowRestoration(_ startup: any WindowStarting, router: any WindowRouting, attempt: Int,
                           network: Binding<Network>, section: Binding<WalletSection>) -> some View {
        modifier(WindowRestoration(network: network, section: section, startup: startup, router: router,
                                   attempt: attempt))
    }
}
