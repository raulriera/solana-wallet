import Testing
@testable import RPC

/// Tests diagnostic redaction independently of HTTP requests and error decoding.
struct SimulationRedactionTests {
    /// Verifies that nested text is sanitized while diagnostic structure and numbers survive.
    @Test
    func `Simulation redaction removes secrets while preserving error structure and numeric diagnostics`() {
        let redactor: any TextRedactor = SecretRedactor(secrets: ["test-key"])
        let simulation = SimulateTransaction.Value(
            error: TransactionError(name: "test-key", details: .array([
                .integer(0), .object(["test-key": .array([.string("test-key"), .integer(UInt64.max)])])
            ])),
            logs: ["Program log: test-key", "Program failed"], unitsConsumed: 150,
            loadedAccountsDataSize: 142, fee: 5000,
            replacementBlockhash: GetLatestBlockhash.Value(blockhash: "test-key", lastValidBlockHeight: UInt64.max),
            preBalances: [1_000_000, 0], postBalances: [994_999, 1],
            preTokenBalances: [balance(amount: 5)], postTokenBalances: [balance(amount: 0)]
        )

        let result = redactor.redact(simulation)

        #expect(result == SimulateTransaction.Value(
            error: TransactionError(name: "[redacted]", details: .array([
                .integer(0), .object(["[redacted]": .array([.string("[redacted]"), .integer(UInt64.max)])])
            ])),
            logs: ["Program log: [redacted]", "Program failed"], unitsConsumed: 150,
            loadedAccountsDataSize: 142, fee: 5000,
            replacementBlockhash: GetLatestBlockhash.Value(blockhash: "[redacted]", lastValidBlockHeight: UInt64.max),
            preBalances: [1_000_000, 0], postBalances: [994_999, 1],
            preTokenBalances: [balance(amount: 5)], postTokenBalances: [balance(amount: 0)]
        ))
    }

    /// Creates a token balance observation for one raw amount.
    /// - Parameter amount: The balance in raw units.
    /// - Returns: A USDC balance attributed to a public address.
    private func balance(amount: UInt64) -> SimulateTransaction.TokenBalance {
        SimulateTransaction.TokenBalance(
            accountIndex: 1, mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            owner: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM", amount: amount, decimals: 6
        )
    }
}
