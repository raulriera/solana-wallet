extension TransactionReviewModel where Proposal == BalanceMoveProposal {
    /// Whether the move is being sent, or was sent and didn't drop.
    var isCommitted: Bool { isSending || (record != nil && outcome != .dropped) }
}
