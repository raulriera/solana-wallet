@testable import Privacy
import Testing
import Transactions

/// Verifies that private spends redact their amounts and nullifiers.
struct PrivateSpendTests {
    /// Verifies that printing, dumping, and reflecting a spend omit its values.
    @Test
    func `Spend diagnostics omit the values`() throws {
        let spend = PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), lamports: 4, receivedLamports: 6,
            nullifiers: [TransferVectors.blinding(0x11)]
        )
        var dumped = ""
        dump(spend, to: &dumped)

        #expect(String(describing: spend) == "PrivateSpend")
        #expect(String(reflecting: spend) == "PrivateSpend")
        #expect(dumped == "- PrivateSpend\n")
    }
}
