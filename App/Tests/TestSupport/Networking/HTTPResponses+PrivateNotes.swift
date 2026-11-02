@testable import RPC

extension HTTPResponses {
    nonisolated static let indexerPosition = "AQ=="

    static func privateNotes(registry: [String] = [], deposits: [String] = [], depositsPerPage: Int? = nil,
                             spends: [String] = [], error: RPCError? = nil,
                             failingMethod: String? = nil, gate: Suspension? = nil, heldMethod: String? = nil,
                             outputTreeID: UInt16? = nil, prover: StubProver? = nil,
                             respond: Responder? = nil) -> HTTPResponses {
        var responses = [
            GetShieldedTransactionsByTags.method: [indexerPage([], in: "transactions", outputTreeID: outputTreeID)],
            GetEncryptedUtxosByTags.method: indexerPages(deposits, in: "matches", perPage: depositsPerPage,
                                                         outputTreeID: outputTreeID),
            GetShieldedTransactionsByNullifiers.method: [indexerPage(spends, in: "transactions")],
        ]
        if !registry.isEmpty { responses[GetMultipleAccounts.method] = registry }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod,
                             prover: prover, respond: respond)
    }

    nonisolated static func indexerPage(_ rows: [String], in field: String, next: String? = nil,
                                        outputTreeID: UInt16? = nil) -> String {
        let tree = outputTreeID.map { #","outputTreeId":\#($0)"# } ?? ""
        let end = next.map { #""nextCursor":"\#($0)""# } ?? #""nextCursor":null,"scannedThrough":"\#(indexerPosition)""#
        return #"{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],\#(end)\#(tree)}"#
    }

    private nonisolated static func indexerPages(_ rows: [String], in field: String, perPage: Int?,
                                                 outputTreeID: UInt16? = nil) -> [String] {
        guard let perPage, rows.count > perPage else {
            return [indexerPage(rows, in: field, outputTreeID: outputTreeID)]
        }
        let pages = rows.batches(of: perPage)
        return pages.enumerated().map { number, page in
            let next = number < pages.count - 1 ? PageCursor.cursor(forPage: number + 1) : nil
            return indexerPage(page, in: field, next: next, outputTreeID: outputTreeID)
        }
    }
}
