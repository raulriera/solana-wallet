import Foundation
import RPC
import Testing
@testable import widgets

struct TransactionOutcomeExplorerTests {
    @Test(arguments: [
        (Network.mainnet, "https://explorer.solana.com/tx/\(ExternalFixture.signature)"),
        (.devnet, "https://explorer.solana.com/tx/\(ExternalFixture.signature)?cluster=devnet"),
    ])
    func `A transaction links to its page on its network`(network: Network, url: String) {
        let outcome = TransactionOutcome(signature: ExternalFixture.signature, network: network,
                                         lastValidBlockHeight: 1, status: .pending)

        #expect(outcome.explorerURL.absoluteString == url)
    }
}
