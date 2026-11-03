/// The additional payments that a transaction-submission service requires.
public struct SubmissionRequirements: Sendable {
    public let tipRecipient: String
    public let tipLamports: UInt64
    /// The minimum total priority fee in lamports, separate from the tip.
    public let minimumPriorityFeeLamports: UInt64

    /// Creates payment requirements.
    ///
    /// - Parameters:
    ///   - tipRecipient: The address that receives the tip.
    ///   - tipLamports: The tip in lamports.
    ///   - minimumPriorityFeeLamports: The minimum total priority fee in lamports.
    init(tipRecipient: String, tipLamports: UInt64, minimumPriorityFeeLamports: UInt64) {
        self.tipRecipient = tipRecipient
        self.tipLamports = tipLamports
        self.minimumPriorityFeeLamports = minimumPriorityFeeLamports
    }
}
