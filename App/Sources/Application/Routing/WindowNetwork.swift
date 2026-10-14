import RPC
import SwiftUI

/// Keeps a window's portfolio on the network that the window shows, and returns the window to Mainnet after a reset.
private struct WindowNetwork: ViewModifier {
    @Binding var network: Network
    let portfolio: WindowPortfolio
    let resetRevision: Revision

    /// Replaces the portfolio when the network changes, and chooses Mainnet each time any window resets the app.
    /// - Parameter content: The window's root destinations.
    /// - Returns: Content whose portfolio follows the window's network.
    func body(content: Content) -> some View {
        content
            .onChange(of: network) { portfolio.show(network) }
            // A reset deletes every wallet, so each window's next wallet starts on Mainnet.
            .onChange(of: resetRevision.value) { network = .mainnet }
    }
}

extension View {
    /// Keeps a window's portfolio on the window's network, and returns the window to Mainnet after any window resets
    /// the app.
    /// - Parameters:
    ///   - network: The network that the window shows, which Settings changes.
    ///   - portfolio: The window's portfolio, replaced when the network changes.
    ///   - resetRevision: The shared count of app resets.
    /// - Returns: A view whose portfolio follows the window's network.
    func windowNetwork(_ network: Binding<Network>, portfolio: WindowPortfolio, resetRevision: Revision) -> some View {
        modifier(WindowNetwork(network: network, portfolio: portfolio, resetRevision: resetRevision))
    }
}
