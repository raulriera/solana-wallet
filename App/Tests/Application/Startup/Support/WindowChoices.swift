import Observation
import RPC
@testable import widgets

/// Holds a hosted window's network and section in place of its scene storage, so a test can change them as Settings
/// and the tab bar do.
@MainActor
@Observable
final class WindowChoices {
    /// The network that the hosted window shows.
    var network: Network
    /// The section that the hosted window shows.
    var section: WalletSection

    /// Starts the hosted window on a network and a section.
    /// - Parameters:
    ///   - network: The network that the window shows first.
    ///   - section: The section that the window shows first.
    init(network: Network, section: WalletSection) {
        self.network = network
        self.section = section
    }
}
