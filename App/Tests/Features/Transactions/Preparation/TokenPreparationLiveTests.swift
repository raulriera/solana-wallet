import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct TokenPreparationLiveTests {
    @Test(arguments: [
        "So11111111111111111111111111111111111111112", "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP",
    ])
    func `Mainnet token preparation reports a missing source account`(_ mintAddress: String) async throws {
        let rpc = try LiveClients.client()
        let account = Account(id: UUID(), recoveryID: UUID(), address: try Address(PublicWallet.address),
                              path: try DerivationPath("m/44'/501'/0'"))
        let mint = try Address(mintAddress)
        let coordinator = try TransactionCoordinator(rpc: rpc,
            store: UnavailableRecoveryStore())
        let source = try #require(try await Wallet().accounts(for: RecoveryPhrase(PublicWallet.words),
                                                              passphrase: "missing-token-source", paths: [.solana]).first)
        let absent = try Address(source.address)

        await #expect(throws: TokenTransfersError.missingAccount(absent)) {
            try await coordinator.transfer(1, token: mint, using: account, to: account.address, source: absent, memo: nil)
        }
    }
}
