import RPC

extension HTTPResponses {
    /// Supplies one twenty-address observation through the real RPC client's transport boundary.
    /// - Parameters:
    ///   - fundedOffsets: Positions in the ordered scan with a positive SOL balance.
    ///   - error: An optional HTTP or transport failure.
    ///   - gate: An optional suspension before returning the HTTP response.
    /// - Returns: A request-recording transport for deterministic onboarding orchestration checks.
    static func discovery(fundedOffsets: Set<Int> = [], error: RPCError? = nil,
                          gate: Suspension? = nil) -> HTTPResponses {
        let funded = #"{"owner":"11111111111111111111111111111111","lamports":1,"executable":false,"data":["","base64"]}"#
        let values = (0..<20).map { fundedOffsets.contains($0) ? funded : "null" }
        let response = #"{"context":{"slot":400},"value":[\#(values.joined(separator: ","))]}"#
        return HTTPResponses(["getMultipleAccounts": [response]], error: error, gate: gate)
    }
}
