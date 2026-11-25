import CryptoKit
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct UserRegistryTests {
    @Test(arguments: try RegistryVectors.load().records)
    func `Records match the independent reference`(_ vector: RegistryVectors.Record) throws {
        let record = try UserRegistry.record(of: Address(vector.owner))

        #expect(record.address.value == vector.record)
        #expect(record.bump == vector.bump)
    }

    @Test(arguments: try RegistryVectors.load().records)
    func `Records decode to recipients`(_ vector: RegistryVectors.Record) throws {
        let recipient = try #require(try UserRegistry.recipient(of: Address(vector.owner), from: Self.account(fixtureBytes(vector.data))))

        #expect(recipient.signingAddress.value == vector.owner)
        #expect(recipient.nullifierPublicKey.bigEndianBytes == (try fixtureBytes(vector.nullifierPublicKey)))
        #expect([UInt8](recipient.viewingPublicKey.taggedRepresentation) == (try fixtureBytes(vector.viewingPublicKey)))
        #expect(recipient.owner.bigEndianBytes == (try fixtureBytes(vector.ownerHash)))
    }

    @Test
    func `Unregistered owners have no recipient`() throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let owner = try Address(vector.owner)
        let donation = Account(owner: "11111111111111111111111111111111", lamports: 1, executable: false, data: Data(try fixtureBytes(vector.data)))

        #expect(try UserRegistry.recipient(of: owner, from: nil) == nil)
        #expect(try UserRegistry.recipient(of: owner, from: donation) == nil)
    }

    @Test(arguments: [
        (99..<100, [], .invalidLength),
        (0..<1, [2], .invalidDiscriminator),
        (1..<2, [0x00], .ownerMismatch),
        (33..<34, [254], .nonCanonicalBump),
        (34..<66, [UInt8](repeating: 0xff, count: 32), .invalidNullifierPublicKey),
        (66..<67, [2], .invalidViewingPublicKey),
        (67..<99, X25519Fixtures.modulus, .invalidViewingPublicKey),
        (99..<100, [2], .invalidMergingFlag),
    ] as [(Range<Int>, [UInt8], UserRegistry.ValidationError)])
    func `Invalid records are rejected`(range: Range<Int>, bytes: [UInt8], error: UserRegistry.ValidationError) throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let data = try fixtureBytes(vector.data).replacingSubrange(range, with: bytes)

        #expect(throws: error) {
            try UserRegistry.recipient(of: Address(vector.owner), from: Self.account(data))
        }
    }

    @Test
    func `Lookups read every record at once`() async throws {
        let vectors = try RegistryVectors.load().records
        let owners = try [vectors[0].owner, vectors[1].owner, vectors[0].owner].map(Address.init)
        let record = try fixtureBytes(vectors[0].data)
        let transport = StubTransport.replying(accounts: [
            AccountReplies.account(owner: try RegistryVectors.load().program, data: record),
            nil,
            AccountReplies.systemAccount(lamports: 1),
        ])

        let recipients = try await UserRegistry.recipients(of: owners, using: SolanaRPC(network: .devnet, transport: transport))

        let requests = await transport.requests
        let request = try #require(requests.first)
        let body = try requestBody(request)
        let params = try #require(body["params"] as? [Any])
        #expect(requests.count == 1)
        #expect(body["method"] as? String == "getMultipleAccounts")
        #expect(try requestedAddresses(request) == [vectors[0].record, vectors[1].record, vectors[0].record])
        #expect((params.last as? [String: Any])?["commitment"] as? String == "finalized")
        #expect(recipients.map { $0?.signingAddress.value } == [vectors[0].owner, nil, nil])
    }

    private static func account(_ data: [UInt8]) throws -> Account {
        Account(owner: try RegistryVectors.load().program, lamports: 1, executable: false, data: Data(data))
    }
}
