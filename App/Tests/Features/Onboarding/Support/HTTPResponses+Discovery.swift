import RPC

extension HTTPResponses {
    static func discovery(fundedOffsets: Set<Int> = [], error: RPCError? = nil,
                          gate: Suspension? = nil) -> HTTPResponses {
        let funded = AccountReplies.systemAccount(lamports: 1)
        let values = (0..<20).map { fundedOffsets.contains($0) ? funded : nil }
        return HTTPResponses(["getMultipleAccounts": [AccountReplies.accounts(values)]], error: error, gate: gate)
    }
}
