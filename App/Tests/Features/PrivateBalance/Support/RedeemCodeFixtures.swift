import Encoding
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Local responses for redeem codes: accounts by address, a registration record's rent, a tree's fee, and proofs, and
/// the tag reads that they record.
enum RedeemCodeFixtures {
    /// The rent of a registration record that every rent read returns.
    static let rent: UInt64 = 1_330_960

    /// The fee per nullifier of tree 1.
    static let treeFee: UInt64 = 108

    /// The reserve of a code whose note lands in tree 1: the rent, two signatures, and one tree fee.
    static let reserve: UInt64 = rent + 10_000 + treeFee

    /// Answers private-note reads with one page per stream, `getMultipleAccounts` by address, rent reads, and proofs.
    /// - Parameters:
    ///   - accounts: Each address's account JSON object; other addresses are missing.
    ///   - deposits: The encrypted-output rows of every tag read.
    ///   - spends: The transaction rows of every spend read, such as ``spend(of:to:leafIndex:)``; none by default.
    ///   - outputTreeID: The output tree that every tag read reports.
    /// - Returns: A request-recording transport whose spend reads find `spends`.
    /// - Throws: A fixture error, which doesn't happen.
    static func responses(accounts: [String: String], deposits: [String], spends: [String] = [],
                          outputTreeID: UInt16? = 1) throws -> HTTPResponses {
        var accounts = accounts
        accounts[try ShieldedPool.tree(id: 1).value] = try tree(fee: treeFee)
        let known = accounts
        return HTTPResponses.privateNotes(deposits: deposits, spends: spends, outputTreeID: outputTreeID) { request in
            switch try request.jsonBody()["method"] as? String {
            case GetMultipleAccounts.method?:
                let addresses = try #require(try request.rpcParameters.first as? [String])
                return #"{"context":{"slot":7},"value":[\#(addresses.map { known[$0] ?? "null" }.joined(separator: ","))]}"#
            case GetMinimumBalanceForRentExemption.method?:
                return String(rent)
            default:
                return try PrivateBalanceFixtures.proof(answering: request)
            }
        }
    }

    /// A system account that holds lamports and no data, such as a one-time account.
    /// - Parameter lamports: The account's lamports.
    /// - Returns: The account's JSON object.
    static func systemAccount(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    /// A tree account of the shielded-pool program with a fee per nullifier at offset 8.
    /// - Parameter fee: The fee per nullifier.
    /// - Returns: The account's JSON object.
    /// - Throws: A fixture error, which doesn't happen.
    static func tree(fee: UInt64) throws -> String {
        let data = [UInt8](repeating: 0, count: 8) + withUnsafeBytes(of: fee.littleEndian, Array.init)
        return #"{"owner":"\#(try ShieldedPool.program.value)","lamports":1,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    /// The address of the registration record of an account.
    /// - Parameter account: The account.
    /// - Returns: The record's base-58 address.
    /// - Throws: A derivation error, which doesn't happen.
    static func recordAddress(of account: widgets.Account) throws -> String {
        try UserRegistry.record(of: account.address).address.value
    }

    /// A proofless deposit of SOL to a one-time account in tree 1.
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - oneTime: The receiving one-time account.
    ///   - leafIndex: The output's position, which also sets the row's signature.
    /// - Returns: The row's JSON object.
    /// - Throws: A fixture error, which doesn't happen.
    static func deposit(_ lamports: UInt64, to oneTime: OneTimeAccount, leafIndex: UInt64) throws -> String {
        try PrivateBalanceFixtures.deposit(lamports, to: oneTime.shieldedAccount, leafIndex: leafIndex)
    }

    /// A confidential transaction that spends a one-time account's fixture deposit, as a row of a spend read.
    /// - Parameters:
    ///   - lamports: The deposit's amount.
    ///   - oneTime: The one-time account that received the deposit.
    ///   - leafIndex: The deposit's position in tree 1.
    /// - Returns: The row's JSON object, which publishes the deposit's nullifier and has no outputs.
    /// - Throws: A fixture error, which doesn't happen.
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

    /// The signature of a fixture deposit row at a leaf index.
    /// - Parameter leafIndex: The deposit's position.
    /// - Returns: The row's base-58 signature.
    static func signature(ofDepositAt leafIndex: UInt64) -> String {
        Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 1), count: 64))
    }

    /// Counts the view tags of each confidential-transaction tag read sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: Each tag read's number of tags, in arrival order.
    /// - Throws: A test prerequisite error for a tag read without tags.
    static func tagCounts(of responses: HTTPResponses) async throws -> [Int] {
        try await responses.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByTags.method }.map {
            try #require(($0.jsonBody()["params"] as? [String: Any])?["tags"] as? [String]).count
        }
    }
}
