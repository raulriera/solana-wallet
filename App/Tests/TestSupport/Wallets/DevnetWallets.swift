import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct DevnetWallets {
    private static let recoveryID = UUID(uuidString: "FDA62506-34AD-426E-8D35-344F45A1B605")!
    private static let senderID = UUID(uuidString: "E2F59EC9-C897-4B39-86A8-84BAE59227AC")!
    private static let recipientID = UUID(uuidString: "9B0AAB8B-85A5-4CB7-91F3-0DB5DFA46B68")!

    let recovery: Recovery
    let sender: widgets.Account
    let recipient: widgets.Account

    static func configured() async throws -> DevnetWallets {
        let seed = try #require(ProcessInfo.processInfo.environment["DEVNET_TEST_SEED"],
                                "DEVNET_TEST_SEED must be configured for devnet tests")
        try #require(!seed.isEmpty && !seed.hasPrefix("$("), "DEVNET_TEST_SEED must be configured for devnet tests")
        let recovery = Recovery(phrase: try RecoveryPhrase(seed), passphrase: "")
        return DevnetWallets(recovery: recovery,
                             sender: try await account(senderID, at: .solana, from: recovery),
                             recipient: try await account(recipientID, at: try DerivationPath("m/44'/501'/1'/0'"), from: recovery))
    }

    func requireFunds(_ lamports: UInt64, using rpc: some RPC) async throws {
        let funds = try await rpc.accounts(at: [sender.address.value])
        try #require((funds.value.first ?? nil)?.lamports ?? 0 >= lamports,
                     "Account 0 must hold \(lamports) lamports of devnet SOL; fund \(sender.address.value)")
    }

    private static func account(_ id: UUID, at path: DerivationPath,
                                from recovery: Recovery) async throws -> widgets.Account {
        let derived = try #require(try await Wallet().accounts(for: recovery.phrase, passphrase: recovery.passphrase,
                                                               paths: [path]).first)
        return widgets.Account(id: id, recoveryID: recoveryID, address: try Address(derived.address), path: path)
    }
}
