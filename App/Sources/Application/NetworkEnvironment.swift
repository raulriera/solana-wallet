import RPC
import SwiftUI

extension EnvironmentValues {
    /// The network that the owning window shows, with Mainnet as a fallback.
    @Entry var network = Network.mainnet
}
