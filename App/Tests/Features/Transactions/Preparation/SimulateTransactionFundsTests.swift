import RPC
import Testing
@testable import widgets

struct SimulateTransactionFundsTests {
    private static let transferError = TransactionError(name: "InstructionError",
                                                        details: .array([.integer(0), .object(["Custom": .integer(1)])]))

    @Test(arguments: [
        (SimulateTransactionFundsTests.value(error: nil, logs: ["Transfer: insufficient lamports 0, need 1000"]), false),
        (SimulateTransactionFundsTests.value(error: TransactionError(name: "InsufficientFundsForFee", details: nil)), true),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.rentError(at: 0)), true),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.rentError(at: 1)), false),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.transferError,
                                             logs: ["Program 11111111111111111111111111111111 invoke [1]",
                                                    "Transfer: insufficient lamports 0, need 1000"]), true),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.transferError,
                                             logs: ["Program 11111111111111111111111111111111 failed: custom program error: 0x1"]),
         false),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.transferError, logs: nil), false),
    ])
    func `Only executions that run out of SOL lack funds`(value: SimulateTransaction.Value, lacksFunds: Bool) {
        #expect(value.lacksFunds == lacksFunds)
    }

    @Test(arguments: [
        (SimulateTransactionFundsTests.value(error: nil), false),
        (SimulateTransactionFundsTests.value(error: TransactionError(name: "InsufficientFundsForFee", details: nil)), false),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.rentError(at: 0)), false),
        (SimulateTransactionFundsTests.value(error: SimulateTransactionFundsTests.rentError(at: 1)), true),
    ])
    func `Only rent errors on another account open an account below rent`(value: SimulateTransaction.Value,
                                                                          opensAccountBelowRent: Bool) {
        #expect(value.opensAccountBelowRent == opensAccountBelowRent)
    }

    private static func rentError(at index: UInt64) -> TransactionError {
        TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(index)]))
    }

    private static func value(error: TransactionError?, logs: [String]? = []) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: logs, unitsConsumed: 150, loadedAccountsDataSize: 256, fee: 5_000,
                                  replacementBlockhash: nil, preBalances: nil, postBalances: nil, preTokenBalances: nil,
                                  postTokenBalances: nil)
    }
}
