import RPC
import Testing
@testable import widgets

/// Verifies that prepared private transactions describe themselves without their values.
struct PreparedPrivateTransactionTests {
    /// Printing, dumping, and reflecting a prepared transaction omit its account, amounts, and instructions.
    @Test
    func `Prepared transaction diagnostics omit the values`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let transaction = PreparedPrivateTransaction(instructions: [], account: account, network: .devnet,
                                                     effect: .deposit(5_000), registers: true)
        var dumped = ""
        dump(transaction, to: &dumped)

        #expect(String(describing: transaction) == "PreparedPrivateTransaction")
        #expect(String(reflecting: transaction) == "PreparedPrivateTransaction")
        #expect(dumped == "- PreparedPrivateTransaction\n")
    }
}
