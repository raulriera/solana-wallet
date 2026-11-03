import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

struct RegistrationTests {
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

    @Test
    func `Accounts without a record are unregistered`() async throws {
        let transport = Self.transport(returning: "null")

        let registration = try await TransferVectors.sender().registration(using: Solana(network: .devnet, transport: transport))

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
        let transport = try Self.transport(returning: Self.record(fixtureBytes(vector.data)))

        let registration = try await account.registration(using: Solana(network: .devnet, transport: transport))

        #expect(registration == .registeredWithOtherKeys)
    }

    @Test
    func `Malformed records fail`() async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = try Self.transport(returning: Self.record(Array(fixtureBytes(vector.data).dropLast())))

        await #expect(throws: UserRegistry.ValidationError.invalidLength) {
            try await TransferVectors.sender().registration(using: Solana(network: .devnet, transport: transport))
        }
    }

    private static func record(_ data: [UInt8]) throws -> String {
        #"{"owner":"\#(try RegistryVectors.load().program)","lamports":1,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    private static func transport(returning account: String) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(account)]}"#)
        }
    }
}
