import Testing
@testable import RPC

struct SenderTests {
    @Test(arguments: [
        (Sender.Tier.standard, UInt64(5_000)),
        (.premium, UInt64(1_000_000)),
    ])
    func `Each tier's submissions pay Helius's published tip to a Sender tip account`(tier: Sender.Tier,
                                                                                      tipLamports: UInt64) {
        let sender = Sender(tier: tier)

        #expect(sender.network == .mainnet)
        #expect(sender.submissionRequirements.tipLamports == tipLamports)
        #expect(Sender.tipAccounts.contains(sender.submissionRequirements.tipRecipient))
    }
}
