import Foundation
@testable import Privacy
@testable import RPC
import Testing

/// Verifies the read of a tree's fee per nullifier through a real RPC client with local responses.
struct ShieldedPoolTreeFeeTests {
    /// The shielded-pool program's address.
    static let program = "sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6"

    /// Verifies that the fee is the little-endian 64-bit integer at offset 8 of the tree's account,
    /// read with one `getMultipleAccounts` read of the tree's address.
    @Test
    func `Fees decode from the tree account`() async throws {
        let header: [UInt8] = [1, 1, 7, 0, 0xff, 0xff, 0xff, 0xff]
        let fee: [UInt8] = [0x6c, 0x01, 0, 0, 0, 0, 0, 0x02]
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: header + fee + [0xee, 0xee]))

        let result = try await ShieldedPool.feePerNullifier(treeID: 7, using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(result == 0x0200_0000_0000_016c)
        #expect(requests.map { $0["method"] as? String } == ["getMultipleAccounts"])
        #expect(requests.first.flatMap { ($0["params"] as? [Any])?.first as? [String] } == ["4q8pT6x2J6b75gFFGjT3Fayh4jQMimTWpUVWQgVVmHiq"])
    }

    /// Verifies that an account of exactly 16 bytes holds the fee.
    @Test
    func `Sixteen bytes hold the fee`() async throws {
        let data = [UInt8](repeating: 0, count: 8) + [108, 0, 0, 0, 0, 0, 0, 0]
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: data))

        let result = try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana(network: .devnet, transport: transport))

        #expect(result == 108)
    }

    /// Verifies that a missing account, an account of another program, a short account, and a
    /// response of another length fail the read.
    ///
    /// - Parameters:
    ///   - accounts: The response's accounts, as JSON.
    ///   - error: The expected error.
    @Test(arguments: [
        ("null", ShieldedPool.TreeError.missingTree),
        (account(owner: "11111111111111111111111111111111", data: [UInt8](repeating: 0, count: 16)), .foreignOwner),
        (account(owner: program, data: [UInt8](repeating: 0, count: 15)), .invalidLength),
        ("", .mismatchedResponse),
        ("null,null", .mismatchedResponse),
    ])
    func `Accounts without a fee schedule fail`(accounts: String, error: ShieldedPool.TreeError) async throws {
        let transport = Self.transport(returning: accounts)

        await #expect(throws: error) {
            try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana(network: .devnet, transport: transport))
        }
    }

    /// Creates the JSON of an account.
    ///
    /// - Parameters:
    ///   - owner: The account's owner program.
    ///   - data: The account's data.
    /// - Returns: The account's JSON object.
    static func account(owner: String, data: [UInt8]) -> String {
        #"{"owner":"\#(owner)","lamports":1000000,"executable":false,"data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    /// Creates a transport that answers every `getMultipleAccounts` read with the given accounts.
    ///
    /// - Parameter accounts: The accounts' JSON, separated by commas.
    /// - Returns: The transport.
    private static func transport(returning accounts: String) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(accounts)]}"#)
        }
    }
}
