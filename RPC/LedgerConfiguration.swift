/// The shared confirmation and evaluation limits for ledger requests.
struct LedgerConfiguration: Encodable {
    /// The confirmation level requested for the ledger state.
    let commitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    let minContextSlot: UInt64?
}
