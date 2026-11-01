import Encoding
import Foundation
import ModularArithmetic
import Testing
import Transactions
import Wallet
@testable import Privacy
@testable import RPC
@testable import widgets

enum RedeemCodeFixtures {
    static let rent: UInt64 = 1_330_960

    static let treeFee: UInt64 = 108

    static let reserve: UInt64 = rent + 10_000 + treeFee

    static func responses(accounts: [String: String], deposits: [String], spends: [String] = [],
                          outputTreeID: UInt16? = 1) throws -> HTTPResponses {
        var accounts = accounts
        accounts[try ShieldedPool.tree(id: 1).value] = try tree(fee: treeFee)
        let known = accounts
        return HTTPResponses.privateNotes(deposits: deposits, spends: spends, outputTreeID: outputTreeID,
                                          prover: try IndexedProofs.prover()) { request in
            switch try request.jsonBody()["method"] as? String {
            case GetMultipleAccounts.method?:
                let addresses = try #require(try request.rpcParameters.first as? [String])
                return #"{"context":{"slot":7},"value":[\#(addresses.map { known[$0] ?? "null" }.joined(separator: ","))]}"#
            case GetMinimumBalanceForRentExemption.method?:
                return String(rent)
            default:
                return try #require(nil as String?, "Unexpected request")
            }
        }
    }

    static func systemAccount(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    static func tree(fee: UInt64) throws -> String {
        let data = [UInt8](repeating: 0, count: 8) + withUnsafeBytes(of: fee.littleEndian, Array.init)
        return #"{"owner":"\#(try ShieldedPool.program.value)","lamports":1,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    static func recordAddress(of account: widgets.Account) throws -> String {
        try UserRegistry.record(of: account.address).address.value
    }

    static func deposit(_ lamports: UInt64, to oneTime: OneTimeAccount, leafIndex: UInt64) throws -> String {
        try PrivateBalanceFixtures.deposit(lamports, to: oneTime.shieldedAccount, leafIndex: leafIndex)
    }

    static func spend(of lamports: UInt64, to oneTime: OneTimeAccount, leafIndex: UInt64) throws -> String {
        let account = try oneTime.shieldedAccount
        let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: 1), leafIndex: leafIndex)
        let utxo = UTXO(owner: try account.recipient.owner, mint: [UInt8](repeating: 0, count: 32), amount: lamports,
                        blinding: blinding, treeID: 1)
        let nullifier = Base58.encode(utxo.nullifier(using: account.nullifierKey).bigEndianBytes)
        let signature = Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 101), count: 64))
        return #"{"slot":4,"txSignature":"\#(signature)","txViewingPk":null,"salt":null,"outputSlots":[],"#
            + #""nullifiers":["\#(nullifier)"],"proofless":false}"#
    }

    static func signature(ofDepositAt leafIndex: UInt64) -> String {
        Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 1), count: 64))
    }

    static func tagCounts(of responses: HTTPResponses) async throws -> [Int] {
        try await responses.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByTags.method }.map {
            try #require(($0.jsonBody()["params"] as? [String: Any])?["tags"] as? [String]).count
        }
    }
}
