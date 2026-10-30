/// The commitment, minimum slot, and account data encoding of a ledger request or subscription.
struct LedgerConfiguration: Encodable {
    let commitment = Commitment.finalized

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    let minContextSlot: UInt64?

    /// The account data encoding, or `nil` for a reply without account data.
    let encoding: String?

    /// Creates a finalized configuration for one request or subscription.
    ///
    /// - Parameters:
    ///   - minContextSlot: The earliest evaluation slot, or `nil` for no minimum.
    ///   - includesAccountData: Whether the reply carries account data.
    init(minContextSlot: UInt64? = nil, includesAccountData: Bool = false) {
        self.minContextSlot = minContextSlot
        encoding = includesAccountData ? "base64" : nil
    }
}
