@testable import RPC

extension HTTPResponses {
    static func privateNotes(registry: [String] = [], deposits: [String] = [], depositsPerPage: Int? = nil,
                             spends: [String] = [], error: RPCError? = nil,
                             failingMethod: String? = nil, gate: Suspension? = nil, heldMethod: String? = nil,
                             outputTreeID: UInt16? = nil, prover: StubProver? = nil, trees: UTXOTrees? = nil,
                             respond: Responder? = nil) -> HTTPResponses {
        let depositPages = PageCursor.pages(of: deposits, perPage: depositsPerPage).map { page in
            IndexerReplies.page(page.rows, in: "outputs", next: page.next, outputTreeID: outputTreeID)
        }
        var responses = [
            GetShieldedTransactionsByTags.method: [IndexerReplies.page([], in: "events", outputTreeID: outputTreeID)],
            GetEncryptedUtxosByTags.method: depositPages,
            GetShieldedTransactionsByNullifiers.method: [IndexerReplies.page(spends, in: "events")],
        ]
        if !registry.isEmpty { responses[GetMultipleAccounts.method] = registry }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod,
                             prover: prover, trees: trees ?? UTXOTrees(rows: deposits + spends), respond: respond)
    }
}
