import Testing
@testable import RPC

struct SenderSubmissionProviderTests {
    @Test(arguments: [
        (SenderSubmissionProvider.Tier.standard, UInt64(5_000)),
        (.premium, UInt64(1_000_000)),
    ])
    func `Each tier's submissions pay Helius's published tip to a Sender tip account`(
        tier: SenderSubmissionProvider.Tier,
        tipLamports: UInt64
    ) {
        let sender = SenderSubmissionProvider(tier: tier)

        #expect(sender.network == .mainnet)
        #expect(sender.submissionRequirements.tipLamports == tipLamports)
        #expect(SenderSubmissionProvider.tipAccounts.contains(sender.submissionRequirements.tipRecipient))
    }
}
