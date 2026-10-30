import Foundation
@testable import Privacy
@testable import RPC
import Testing

struct ShieldedPoolTreeFeeTests {
    static let program = "sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6"

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

    @Test
    func `Sixteen bytes hold the fee`() async throws {
        let data = [UInt8](repeating: 0, count: 8) + [108, 0, 0, 0, 0, 0, 0, 0]
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: data))

        let result = try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana(network: .devnet, transport: transport))

        #expect(result == 108)
    }

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

    static func account(owner: String, data: [UInt8]) -> String {
        #"{"owner":"\#(owner)","lamports":1000000,"executable":false,"data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    private static func transport(returning accounts: String) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(accounts)]}"#)
        }
    }
}
