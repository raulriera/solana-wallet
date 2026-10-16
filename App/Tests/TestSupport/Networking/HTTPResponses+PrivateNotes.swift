@testable import RPC

extension HTTPResponses {
    /// The indexer position that every private-note page reports.
    nonisolated static let indexerPosition = "AQ=="

    /// Answers private-note reads with one page per stream, and registry reads only when given.
    /// - Parameters:
    ///   - registry: The `getMultipleAccounts` results in arrival order, or none, so that a registry read fails the test.
    ///   - deposits: The encrypted-output rows of every tag read, such as proofless deposits.
    ///   - error: An optional transport or HTTP failure.
    ///   - failingMethod: The method to fail, or `nil` to fail every request.
    ///   - gate: An optional suspension for overlap and cancellation checks.
    ///   - heldMethod: The method to suspend, or `nil` to suspend every request.
    /// - Returns: A request-recording transport whose spend reads find no spends.
    static func privateNotes(registry: [String] = [], deposits: [String] = [], error: RPCError? = nil,
                             failingMethod: String? = nil, gate: Suspension? = nil,
                             heldMethod: String? = nil) -> HTTPResponses {
        var responses = [
            GetShieldedTransactionsByTags.method: [indexerPage([], in: "transactions")],
            GetEncryptedUtxosByTags.method: [indexerPage(deposits, in: "matches")],
            GetShieldedTransactionsByNullifiers.method: [indexerPage([], in: "transactions")],
        ]
        if !registry.isEmpty { responses[GetMultipleAccounts.method] = registry }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod)
    }

    /// An indexer stream's only page, as Helius's Solana Rings indexer encodes it.
    /// - Parameters:
    ///   - rows: The rows' JSON objects.
    ///   - field: The `transactions` or `matches` field name.
    /// - Returns: The page's JSON result value.
    nonisolated static func indexerPage(_ rows: [String], in field: String) -> String {
        #"{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],"nextCursor":null,"scannedThrough":"\#(indexerPosition)"}"#
    }
}
