import Observation
import RPC
import SwiftUI
@testable import widgets

/// Holds the wallet that a hosted window shows, so a test can change it as a wallet window does.
@MainActor
@Observable
final class ShownWallet {
    /// The window's account.
    var account: widgets.Account
    /// The window's network.
    var network: Network
    /// The window's scene phase, which a hosted window doesn't have on its own.
    var phase: ScenePhase

    /// Starts the hosted window on a wallet.
    /// - Parameters:
    ///   - account: The account that the window shows first.
    ///   - network: The network that the window shows first, devnet by default, as the transaction fixtures are.
    ///   - phase: The window's scene phase at first.
    init(_ account: widgets.Account, on network: Network = .devnet, phase: ScenePhase = .active) {
        self.account = account
        self.network = network
        self.phase = phase
    }
}
