/// The additional payment requirements of an optional submission service.
public struct SubmissionRequirements: Sendable {
    /// The SOL destination that must receive the service's tip.
    public let tipRecipient: String
    /// The required tip in lamports, separate from the network fee.
    public let tipLamports: UInt64
    /// The minimum total priority fee in lamports, separate from the tip.
    public let minimumPriorityFeeLamports: UInt64

    /// Creates payment requirements to include before transaction review and signing.
    ///
    /// - Parameters:
    ///   - tipRecipient: The service's public tip address.
    ///   - tipLamports: The tip amount in lamports.
    ///   - minimumPriorityFeeLamports: The minimum total priority fee.
    public init(tipRecipient: String, tipLamports: UInt64, minimumPriorityFeeLamports: UInt64) {
        self.tipRecipient = tipRecipient
        self.tipLamports = tipLamports
        self.minimumPriorityFeeLamports = minimumPriorityFeeLamports
    }
}
