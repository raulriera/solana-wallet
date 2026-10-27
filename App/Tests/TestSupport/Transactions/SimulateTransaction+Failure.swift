@testable import RPC

extension SimulateTransaction.Value {
    /// Creates a failed simulation without balances.
    /// - Parameters:
    ///   - error: The execution error.
    ///   - logs: The program logs.
    ///   - fee: The network fee that the simulation reports, in lamports.
    /// - Returns: The execution.
    static func failure(_ error: TransactionError, logs: [String] = [], fee: UInt64) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: logs, unitsConsumed: 150, loadedAccountsDataSize: 256, fee: fee,
                                  replacementBlockhash: nil, preBalances: nil, postBalances: nil,
                                  preTokenBalances: nil, postTokenBalances: nil)
    }
}
