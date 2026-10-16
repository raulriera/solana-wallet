import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies user registry records against an independent implementation, their rejections, and
/// one lookup through a real RPC client with local responses.
struct UserRegistryTests {
    /// Verifies each record's address and canonical bump.
    ///
    /// - Parameter vector: A registered owner.
    @Test(arguments: try RegistryVectors.load().records)
    func `Records match the independent reference`(_ vector: RegistryVectors.Record) throws {
        let record = try UserRegistry.record(of: Address(vector.owner))

        #expect(record.address.value == vector.record)
        #expect(record.bump == vector.bump)
    }

    /// Verifies that a valid record decodes to the owner's shielded address.
    ///
    /// - Parameter vector: A registered owner.
    @Test(arguments: try RegistryVectors.load().records)
    func `Records decode to recipients`(_ vector: RegistryVectors.Record) throws {
        let recipient = try #require(try UserRegistry.recipient(of: Address(vector.owner), from: Self.account(fixtureBytes(vector.data))))

        #expect(recipient.signingAddress.value == vector.owner)
        #expect(recipient.nullifierPublicKey.bigEndianBytes == (try fixtureBytes(vector.nullifierPublicKey)))
        #expect(Array(recipient.viewingPublicKey.compressedRepresentation) == (try fixtureBytes(vector.viewingPublicKey)))
        #expect(recipient.owner.bigEndianBytes == (try fixtureBytes(vector.ownerHash)))
    }

    /// Verifies that a missing account, and one that the registry program doesn't own, mean the
    /// owner hasn't registered.
    @Test
    func `Unregistered owners have no recipient`() throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let owner = try Address(vector.owner)
        let donation = Account(owner: "11111111111111111111111111111111", lamports: 1, executable: false, data: Data(try fixtureBytes(vector.data)))

        #expect(try UserRegistry.recipient(of: owner, from: nil) == nil)
        #expect(try UserRegistry.recipient(of: owner, from: donation) == nil)
    }

    /// Verifies that a record that isn't a valid record of the owner is rejected.
    ///
    /// - Parameters:
    ///   - range: The bytes of the sender's record to replace.
    ///   - bytes: The replacement.
    ///   - error: The expected rejection.
    @Test(arguments: [
        (133..<134, [], .invalidLength),
        (0..<1, [2], .invalidDiscriminator),
        (1..<2, [0x00], .ownerMismatch),
        (33..<34, [254], .nonCanonicalBump),
        (34..<35, [1], .unsupportedP256Owner),
        (34..<35, [2], .invalidOptionTag),
        (35..<67, [UInt8](repeating: 0xff, count: 32), .invalidNullifierPublicKey),
        (67..<68, [4], .invalidViewingPublicKey),
        (100..<101, [2], .invalidMergingFlag),
    ] as [(Range<Int>, [UInt8], UserRegistry.ValidationError)])
    func `Invalid records are rejected`(range: Range<Int>, bytes: [UInt8], error: UserRegistry.ValidationError) throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let data = try fixtureBytes(vector.data).replacingSubrange(range, with: bytes)

        #expect(throws: error) {
            try UserRegistry.recipient(of: Address(vector.owner), from: Self.account(data))
        }
    }

    /// Verifies one lookup of three owners: one finalized `getMultipleAccounts` of their records in
    /// order, which returns a record, no account, and an account that another program owns.
    @Test
    func `Lookups read every record at once`() async throws {
        let vectors = try RegistryVectors.load().records
        let owners = try [vectors[0].owner, vectors[1].owner, vectors[0].owner].map(Address.init)
        let record = try fixtureBytes(vectors[0].data)
        let accounts = [
            #"{"owner":"regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD","lamports":1,"executable":false,"#
                + #""data":["\#(Data(record).base64EncodedString())","base64"]}"#,
            "null",
            #"{"owner":"11111111111111111111111111111111","lamports":1,"executable":false,"data":["","base64"]}"#,
        ]
        let payload = #""result":{"context":{"slot":7},"value":[\#(accounts.joined(separator: ","))]}"#
        let transport = StubTransport { request in try reply(to: request, payload: payload) }

        let recipients = try await UserRegistry.recipients(of: owners, using: Solana(network: .devnet, transport: transport))

        let requests = await transport.requests
        let request = try #require(requests.first)
        let body = try requestBody(request)
        let params = try #require(body["params"] as? [Any])
        #expect(requests.count == 1)
        #expect(body["method"] as? String == "getMultipleAccounts")
        #expect(params.first as? [String] == [vectors[0].record, vectors[1].record, vectors[0].record])
        #expect((params.last as? [String: Any])?["commitment"] as? String == "finalized")
        #expect(recipients.map { $0?.signingAddress.value } == [vectors[0].owner, nil, nil])
    }

    /// Verifies that a response with another number of accounts is rejected.
    @Test
    func `Mismatched responses are rejected`() async throws {
        let owner = try Address(try #require(try RegistryVectors.load().records.first).owner)
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[null,null]}"#)
        }

        await #expect(throws: UserRegistry.ValidationError.mismatchedResponse) {
            try await UserRegistry.recipients(of: [owner], using: Solana(network: .devnet, transport: transport))
        }
    }

    /// Creates an account that the registry program owns.
    ///
    /// - Parameter data: The account's data.
    /// - Returns: The account.
    private static func account(_ data: [UInt8]) -> Account {
        Account(owner: "regyS5rkAcw2YzDJCmTwCTHs2s246FXxbmuRZ42u2PD", lamports: 1_823_520, executable: false, data: Data(data))
    }
}
