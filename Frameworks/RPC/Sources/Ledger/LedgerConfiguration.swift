/// The shared confirmation and evaluation limits for ledger requests.
struct LedgerConfiguration: Encodable {
    /// The confirmation level requested for the ledger state, which is always finalized.
    let commitment = Commitment.finalized

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    let minContextSlot: UInt64?
}
