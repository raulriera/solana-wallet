import RPC
import Testing
@testable import widgets

struct PreparedPrivateTransactionTests {
    @Test
    func `Prepared transaction diagnostics omit the values`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let transaction = PreparedPrivateTransaction(instructions: [], account: account, network: .devnet,
                                                     effect: .deposit(5_000), registers: true,
                                                     authorities: [.account(account)])
        var dumped = ""
        dump(transaction, to: &dumped)

        #expect(String(describing: transaction) == "PreparedPrivateTransaction")
        #expect(String(reflecting: transaction) == "PreparedPrivateTransaction")
        #expect(dumped == "- PreparedPrivateTransaction\n")
    }
}
