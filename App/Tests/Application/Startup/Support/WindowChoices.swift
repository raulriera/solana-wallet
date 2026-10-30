import Observation
import RPC
@testable import widgets

@MainActor
@Observable
final class WindowChoices {
    var network: Network
    var section: WalletSection

    init(network: Network, section: WalletSection) {
        self.network = network
        self.section = section
    }
}
