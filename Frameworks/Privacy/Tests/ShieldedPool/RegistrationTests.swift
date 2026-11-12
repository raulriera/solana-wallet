import CryptoKit
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct RegistrationTests {
    @Test
    func `Records with the account's keys register it`() async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = StubTransport.replying(accounts: [try Self.record(fixtureBytes(vector.data))])

        let registration = try await TransferVectors.sender().registration(using: SolanaRPC(network: .devnet, transport: transport))

        #expect(registration == .registered)
        #expect(try await transport.requests.map(requestedAddresses) == [[vector.record]])
    }

    @Test
    func `Accounts without a record are unregistered`() async throws {
        let transport = StubTransport.replying(accounts: [nil])

        let registration = try await TransferVectors.sender().registration(using: SolanaRPC(network: .devnet, transport: transport))

        #expect(registration == .unregistered)
    }

    @Test(arguments: [(true, false), (false, true)])
    func `Records with other keys don't register the account`(otherNullifierSecret: Bool, otherViewingKey: Bool) async throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        let vector = try #require(try RegistryVectors.load().records.first)
        let account = try ShieldedAccount(
            signingAddress: Address(TransferVectors.senderSigningAddress),
            nullifierSecret: otherNullifierSecret ? SymmetricKey(data: [UInt8](repeating: 1, count: 31)) : rail.nullifierSecretKey(),
            viewingKey: otherViewingKey ? TransferVectors.recipientViewingKey() : rail.viewingKey()
        )
        let transport = StubTransport.replying(accounts: [try Self.record(fixtureBytes(vector.data))])

        let registration = try await account.registration(using: SolanaRPC(network: .devnet, transport: transport))

        #expect(registration == .registeredWithOtherKeys)
    }

    @Test
    func `Malformed records fail`() async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = StubTransport.replying(accounts: [try Self.record(Array(fixtureBytes(vector.data).dropLast()))])

        await #expect(throws: UserRegistry.ValidationError.invalidLength) {
            try await TransferVectors.sender().registration(using: SolanaRPC(network: .devnet, transport: transport))
        }
    }

    private static func record(_ data: [UInt8]) throws -> String {
        AccountReplies.account(owner: try RegistryVectors.load().program, data: data)
    }
}
