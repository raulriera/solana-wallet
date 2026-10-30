import Observation
import RPC
import SwiftUI
@testable import widgets

@MainActor
@Observable
final class ShownWallet {
    var account: widgets.Account
    var network: Network
    var phase: ScenePhase

    init(_ account: widgets.Account, on network: Network = .devnet, phase: ScenePhase = .active) {
        self.account = account
        self.network = network
        self.phase = phase
    }
}
