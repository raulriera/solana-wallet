import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies an account's registration through a real RPC client with local responses, against the
/// sender's independently computed registry record.
struct RegistrationTests {
    /// Verifies that the sender's record, which publishes the sender's keys, registers it, with one
    /// `getMultipleAccounts` read of the record.
    @Test
    func `Records with the account's keys register it`() async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = try Self.transport(returning: Self.record(fixtureBytes(vector.data)))

        let registration = try await TransferVectors.sender().registration(using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(registration == .registered)
        #expect(requests.map { $0["method"] as? String } == ["getMultipleAccounts"])
        #expect(requests.first.flatMap { ($0["params"] as? [Any])?.first as? [String] } == [vector.record])
    }

    /// Verifies that a signing address without a record is unregistered.
    @Test
    func `Accounts without a record are unregistered`() async throws {
        let transport = Self.transport(returning: "null")

        let registration = try await TransferVectors.sender().registration(using: Solana(network: .devnet, transport: transport))

        #expect(registration == .unregistered)
    }

    /// Verifies that the sender's record doesn't register an account with the sender's signing
    /// address but another nullifier key or viewing key.
    ///
    /// - Parameters:
    ///   - otherNullifierSecret: Whether the account has another nullifier secret.
    ///   - otherViewingKey: Whether the account has another viewing key.
    @Test(arguments: [(true, false), (false, true)])
    func `Records with other keys don't register the account`(otherNullifierSecret: Bool, otherViewingKey: Bool) async throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        let vector = try #require(try RegistryVectors.load().records.first)
        let account = try ShieldedAccount(
            signingAddress: Address(TransferVectors.senderSigningAddress),
            nullifierSecret: otherNullifierSecret ? SymmetricKey(data: [UInt8](repeating: 1, count: 31)) : rail.nullifierSecretKey(),
            viewingKey: otherViewingKey ? TransferVectors.recipientViewingKey() : rail.viewingKey()
        )
        let transport = try Self.transport(returning: Self.record(fixtureBytes(vector.data)))

        let registration = try await account.registration(using: Solana(network: .devnet, transport: transport))

        #expect(registration == .registeredWithOtherKeys)
    }

    /// Verifies that a malformed record fails the read instead of reading as unregistered.
    @Test
    func `Malformed records fail`() async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = try Self.transport(returning: Self.record(Array(fixtureBytes(vector.data).dropLast())))

        await #expect(throws: UserRegistry.ValidationError.invalidLength) {
            try await TransferVectors.sender().registration(using: Solana(network: .devnet, transport: transport))
        }
    }

    /// Creates the JSON of an account that the registry program owns.
    ///
    /// - Parameter data: The account's data.
    /// - Returns: The account's JSON object.
    private static func record(_ data: [UInt8]) -> String {
        #"{"owner":"regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD","lamports":1823520,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    /// Creates a transport that answers every `getMultipleAccounts` read with one account.
    ///
    /// - Parameter account: The account's JSON object, or `null`.
    /// - Returns: The transport.
    private static func transport(returning account: String) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(account)]}"#)
        }
    }
}
