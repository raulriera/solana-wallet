@testable import Privacy
import Testing
import Transactions

struct PrivateSpendTests {
    @Test
    func `Spend diagnostics omit the values`() throws {
        let spend = PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), lamports: 4, receivedLamports: 6,
            nullifierCount: 2, inputTreeID: 0, nullifiers: [TransferVectors.blinding(0x11)]
        )
        var dumped = ""
        dump(spend, to: &dumped)

        #expect(String(describing: spend) == "PrivateSpend")
        #expect(String(reflecting: spend) == "PrivateSpend")
        #expect(dumped == "- PrivateSpend\n")
    }
}
