/// The shared confirmation, evaluation, and account data limits for ledger requests and subscriptions.
struct LedgerConfiguration: Encodable {
    /// The confirmation level requested for the ledger state, which is always finalized.
    let commitment = Commitment.finalized

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    let minContextSlot: UInt64?

    /// The account data encoding, which is always base64, or `nil` when the reply carries no account data.
    let encoding: String?

    /// Creates finalized limits for one request or subscription.
    /// - Parameters:
    ///   - minContextSlot: The earliest evaluation slot, or `nil` for no minimum.
    ///   - includesAccountData: Whether the reply carries account data, which is then requested as base64.
    init(minContextSlot: UInt64? = nil, includesAccountData: Bool = false) {
        self.minContextSlot = minContextSlot
        encoding = includesAccountData ? "base64" : nil
    }
}
