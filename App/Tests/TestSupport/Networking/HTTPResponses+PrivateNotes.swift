import Testing
@testable import RPC

extension HTTPResponses {
    static func privateNotes(registry: [String] = [], accounts: [String: String]? = nil, deposits: [String] = [],
                             depositsPerPage: Int? = nil, laterDeposits: [String] = [], readsBeforeLaterDeposits: Int = 1,
                             spends: [String] = [], error: RPCError? = nil,
                             failingMethod: String? = nil, gate: Suspension? = nil, heldMethod: String? = nil,
                             outputTreeID: UInt16? = nil, prover: StubProver? = nil, trees: UTXOTrees? = nil,
                             respond: Responder? = nil) -> HTTPResponses {
        let reads = laterDeposits.isEmpty
            ? [deposits] : Array(repeating: deposits, count: readsBeforeLaterDeposits) + [deposits + laterDeposits]
        let depositPages = reads.flatMap { rows in
            PageCursor.pages(of: rows, perPage: depositsPerPage).map { page in
                IndexerReplies.page(page.rows, in: "outputs", next: page.next, outputTreeID: outputTreeID)
            }
        }
        var responses = [
            GetShieldedTransactionsByTags.method: [IndexerReplies.page([], in: "events", outputTreeID: outputTreeID)],
            GetEncryptedUtxosByTags.method: depositPages,
            GetShieldedTransactionsByNullifiers.method: [IndexerReplies.page(spends, in: "events")],
        ]
        if !registry.isEmpty { responses[GetMultipleAccounts.method] = registry }
        var responder = respond
        if let accounts {
            responder = { request in
                guard try request.rpcMethod == GetMultipleAccounts.method else {
                    let other = try #require(respond, "Unexpected request")
                    return try other(request)
                }
                let addresses = try requestedAddresses(request)
                return AccountReplies.accounts(addresses.map { accounts[$0] })
            }
        }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod,
                             prover: prover, trees: trees ?? UTXOTrees(rows: deposits + laterDeposits + spends),
                             respond: responder)
    }
}
