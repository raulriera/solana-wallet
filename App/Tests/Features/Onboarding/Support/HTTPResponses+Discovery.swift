import RPC

extension HTTPResponses {
    static func discovery(fundedOffsets: Set<Int> = [], error: RPCError? = nil,
                          gate: Suspension? = nil) -> HTTPResponses {
        let funded = #"{"owner":"11111111111111111111111111111111","lamports":1,"executable":false,"data":["","base64"]}"#
        let values = (0..<20).map { fundedOffsets.contains($0) ? funded : "null" }
        let response = #"{"context":{"slot":400},"value":[\#(values.joined(separator: ","))]}"#
        return HTTPResponses(["getMultipleAccounts": [response]], error: error, gate: gate)
    }
}
