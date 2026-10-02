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
            replacementBlockhash: GetLatestBlockhash.Value(blockhash: "test-key", lastValidBlockHeight: UInt64.max)
        )

        let result = redactor.redact(simulation)

        #expect(result == SimulateTransaction.Value(
            error: TransactionError(name: "[redacted]", details: .array([
                .integer(0), .object(["[redacted]": .array([.string("[redacted]"), .integer(UInt64.max)])])
            ])),
            logs: ["Program log: [redacted]", "Program failed"], unitsConsumed: 150,
            loadedAccountsDataSize: 142, fee: 5000,
            replacementBlockhash: GetLatestBlockhash.Value(blockhash: "[redacted]", lastValidBlockHeight: UInt64.max)
        ))
    }
}
