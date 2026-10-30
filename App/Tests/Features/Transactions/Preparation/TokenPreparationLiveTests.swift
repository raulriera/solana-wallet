import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

@Suite(.tags(.network))
struct TokenPreparationLiveTests {
    @Test(.timeLimit(.minutes(1)), arguments: TokenProgram.allCases)
    func `Mainnet token preparation reports a missing source account`(_ program: TokenProgram) async throws {
        let rpc = try LiveClients.client()
        let account = Account(id: UUID(), recoveryID: UUID(), address: try Address(PublicWallet.address),
                              path: try DerivationPath("m/44'/501'/0'"))
        let mint = try Address(program == .token ? "So11111111111111111111111111111111111111112"
                                               : "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP")
        let coordinator = try TransactionCoordinator(rpc: rpc,
            store: KeychainStore(service: "widgetsTests.TokenPreparation"))
        let source = try #require(try await Wallet().accounts(for: RecoveryPhrase(PublicWallet.words),
                                                              passphrase: "missing-token-source", paths: [.solana]).first)
        let absent = try Address(source.address)

        await #expect(throws: TokenTransfersError.missingAccount(absent)) {
            try await coordinator.transfer(1, token: mint, using: account, to: account.address, source: absent, memo: nil)
        }
    }
}
