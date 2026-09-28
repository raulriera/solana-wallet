import Foundation
import RPC

/// An app-configured RPC provider whose submission participation is explicit.
nonisolated struct Provider: Identifiable, Sendable {
    /// The stable identifier used to associate submission diagnostics with this provider.
    let id: UUID
    /// The client used for this provider's requests.
    let rpc: any RPC
    /// Whether this provider participates in submission on its network.
    var isEnabled: Bool

    /// Creates a provider selection independently of portfolio capabilities.
    ///
    /// - Parameters:
    ///   - id: The identifier retained when changing the provider's activation.
    ///   - rpc: The client for the selected provider. Solana mainnet is the default.
    ///   - isEnabled: Whether to submit through this provider. The default is `true`.
    init(id: UUID = UUID(), rpc: any RPC = Solana(), isEnabled: Bool = true) {
        self.id = id
        self.rpc = rpc
        self.isEnabled = isEnabled
    }
}
