@testable import RPC

extension HTTPResponses {
    nonisolated static let indexerPosition = "AQ=="

    static func privateNotes(registry: [String] = [], deposits: [String] = [], spends: [String] = [],
                             error: RPCError? = nil,
                             failingMethod: String? = nil, gate: Suspension? = nil, heldMethod: String? = nil,
                             outputTreeID: UInt16? = nil, prove: Responder? = nil) -> HTTPResponses {
        var responses = [
            GetShieldedTransactionsByTags.method: [indexerPage([], in: "transactions", outputTreeID: outputTreeID)],
            GetEncryptedUtxosByTags.method: [indexerPage(deposits, in: "matches", outputTreeID: outputTreeID)],
            GetShieldedTransactionsByNullifiers.method: [indexerPage(spends, in: "transactions")],
        ]
        if !registry.isEmpty { responses[GetMultipleAccounts.method] = registry }
        return HTTPResponses(responses, error: error, failingMethod: failingMethod, gate: gate, heldMethod: heldMethod,
                             respond: prove)
    }

    nonisolated static func indexerPage(_ rows: [String], in field: String, outputTreeID: UInt16? = nil) -> String {
        let tree = outputTreeID.map { #","outputTreeId":\#($0)"# } ?? ""
        return #"{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],"nextCursor":null,"#
            + #""scannedThrough":"\#(indexerPosition)"\#(tree)}"#
    }
}
