import RPC
import Testing
@testable import widgets

/// Verifies which simulated execution failures mean that the payer's SOL didn't cover the transaction.
struct SimulateTransactionFundsTests {
    /// The System Program's custom error 1, which a transfer without enough lamports reports.
    private static let transferError = TransactionError(name: "InstructionError",
                                                        details: .array([.integer(0), .object(["Custom": .integer(1)])]))

    /// Verifies a fee, rent, or transfer that the payer's SOL doesn't cover lacks funds, and other results don't.
    /// - Parameters:
    ///   - value: The simulated execution.
    ///   - lacksFunds: Whether the execution lacks funds.
    @Test(arguments: [
        (SimulateTransactionFundsTests.value(error: nil, logs: ["Transfer: insufficient lamports 0, need 1000"]), false),
        (SimulateTransactionFundsTests.value(error: TransactionError(name: "InsufficientFundsForFee", details: nil)), true),
        (SimulateTransactionFundsTests.value(error: TransactionError(name: "InsufficientFundsForRent",
                                                                     details: .object(["account_index": .integer(1)]))), true),
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

    /// Creates a simulated execution with an error and logs.
    /// - Parameters:
    ///   - error: The execution error, or `nil` for success.
    ///   - logs: The program logs, or `nil` when the node didn't record them.
    /// - Returns: The execution without balances.
    private static func value(error: TransactionError?, logs: [String]? = []) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: logs, unitsConsumed: 150, loadedAccountsDataSize: 256, fee: 5_000,
                                  replacementBlockhash: nil, preBalances: nil, postBalances: nil, preTokenBalances: nil,
                                  postTokenBalances: nil)
    }
}
