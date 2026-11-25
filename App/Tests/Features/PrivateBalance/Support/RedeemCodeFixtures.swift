import Encoding
import Foundation
import Testing
import Transactions
import Wallet
@testable import Privacy
@testable import RPC
@testable import widgets

enum RedeemCodeFixtures {
    static let rent: UInt64 = 1_330_960

    static let treeFee: UInt64 = 108

    static let reserve: UInt64 = rent + 10_000 + 2 * treeFee

    static func responses(accounts: [String: String], deposits: [String], spends: [String] = [],
                          outputTreeID: UInt16? = 1, isFinalized: Bool = true) throws -> HTTPResponses {
        let trees = UTXOTrees(rows: deposits + spends, isFinalized: isFinalized, feePerTree: treeFee)
        return HTTPResponses.privateNotes(accounts: accounts, deposits: deposits, spends: spends,
                                          outputTreeID: outputTreeID, prover: try IndexedProofs.prover(),
                                          trees: trees) { request in
            try #require(request.rpcMethod == GetMinimumBalanceForRentExemption.method, "Unexpected request")
            return String(rent)
        }
    }

    static func recordAddress(of account: widgets.Account) throws -> String {
        try UserRegistry.record(of: account.address).address.value
    }

    static func deposit(_ lamports: UInt64, to oneTime: OneTimeAccount, leafIndex: UInt64) throws -> String {
        try PrivateBalanceFixtures.deposit(lamports, to: oneTime.shieldedAccount, leafIndex: leafIndex, of: .nativeSOL)
    }

    static func spend(of lamports: UInt64, to oneTime: OneTimeAccount, leafIndex: UInt64) throws -> String {
        try PrivateBalanceFixtures.spend(of: lamports, to: oneTime.shieldedAccount, leafIndex: leafIndex)
    }

    static func signature(ofDepositAt leafIndex: UInt64) -> String {
        Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 1), count: 64))
    }

    static func tagCounts(of responses: HTTPResponses) async throws -> [Int] {
        try await responses.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByTags.method }.map {
            try #require((requestBody($0)["params"] as? [String: Any])?["tags"] as? [String]).count
        }
    }
}
