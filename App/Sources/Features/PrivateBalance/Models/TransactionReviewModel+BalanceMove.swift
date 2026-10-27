extension TransactionReviewModel where Proposal == BalanceMoveProposal {
    /// Whether the move left its review for good: it's being signed and sent, or it was sent and didn't drop.
    ///
    /// A committed move used up its typed amount, even when its review closed before the move was recorded. A dropped
    /// move never left the account, so its amount can be reviewed again.
    var isCommitted: Bool { isSending || (record != nil && outcome != .dropped) }
}
