import Foundation
import Testing
@testable import Wallet

/// Verifies the Solana Rings derivation-input guard directly.
struct DerivationInputTests {
    /// Verifies the guard against every zolana vector: bare and off-chain derivation messages, a
    /// truncated payload, an unsupported version, and messages that only resemble the prefix.
    ///
    /// - Parameter vector: A message and whether it's a derivation input.
    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard)
    func `Messages match zolana's derivation-input vectors`(_ vector: PrivateBalanceVectors.GuardVector) throws {
        #expect(Data(try fixtureBytes(vector.message)).isDerivationInput == vector.isDerivationInput)
    }
}
