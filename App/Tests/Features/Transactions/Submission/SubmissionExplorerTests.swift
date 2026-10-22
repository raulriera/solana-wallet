import Foundation
import RPC
import Testing
@testable import widgets

/// Checks that a sent transaction links to its page on Solana Explorer, on its own network.
struct SubmissionExplorerTests {
    /// Mainnet transactions link to Explorer's default network; devnet transactions name the devnet cluster.
    /// - Parameters:
    ///   - network: The transaction's network.
    ///   - url: The expected page.
    @Test(arguments: [
        (Network.mainnet, "https://explorer.solana.com/tx/\(ExternalFixture.signature)"),
        (.devnet, "https://explorer.solana.com/tx/\(ExternalFixture.signature)?cluster=devnet"),
    ])
    func `A transaction links to its page on its network`(network: Network, url: String) {
        let submission = Submission(signature: ExternalFixture.signature, network: network, lastValidBlockHeight: 1)

        #expect(submission.explorerURL.absoluteString == url)
    }
}
