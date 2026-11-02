import Foundation
import Testing
@testable import Privacy
@testable import RPC

struct ShieldedPoolTreeFeeTests {
    static let program = "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW"

    @Test
    func `Fees decode from the tree account`() async throws {
        let header: [UInt8] = [1, 1, 7, 0, 0xff, 0xff, 0xff, 0xff]
        let fee: [UInt8] = [0x6c, 0x01, 0, 0, 0, 0, 0, 0x02]
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: header + fee + [0xee, 0xee]))

        let result = try await ShieldedPool.feePerNullifier(treeID: 7, using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(result == 0x0200_0000_0000_016c)
        #expect(requests.map { $0["method"] as? String } == ["getMultipleAccounts"])
        #expect(requests.first.flatMap { ($0["params"] as? [Any])?.first as? [String] } == ["2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7"])
    }

    @Test
    func `Sixteen bytes hold the fee`() async throws {
        let data = [UInt8](repeating: 0, count: 8) + [108, 0, 0, 0, 0, 0, 0, 0]
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: data))

        let result = try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana(network: .devnet, transport: transport))

        #expect(result == 108)
    }

    @Test
    func `Accounts shorter than the fee schedule fail`() async throws {
        let transport = Self.transport(returning: Self.account(owner: Self.program, data: [UInt8](repeating: 0, count: 15)))

        await #expect(throws: ShieldedPool.TreeError.invalidLength) {
            try await ShieldedPool.feePerNullifier(treeID: 0, using: Solana(network: .devnet, transport: transport))
        }
    }

    static func account(owner: String, data: [UInt8]) -> String {
        #"{"owner":"\#(owner)","lamports":1000000,"executable":false,"data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    static func transport(returning accounts: String) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(accounts)]}"#)
        }
    }
}
