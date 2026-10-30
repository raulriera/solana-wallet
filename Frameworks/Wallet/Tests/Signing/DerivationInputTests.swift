import Foundation
import Testing
@testable import Wallet

struct DerivationInputTests {
    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard)
    func `Messages match zolana's derivation-input vectors`(_ vector: PrivateBalanceVectors.GuardVector) throws {
        #expect(Data(try fixtureBytes(vector.message)).isDerivationInput == vector.isDerivationInput)
    }
}
