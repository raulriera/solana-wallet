import Foundation
import Testing
@testable import Privacy
@testable import RPC

struct ShieldedPoolTreeFeeTests {
    @Test
    func `Fees decode from the tree account`() async throws {
        let transport = Self.transport(returning: [UTXOTrees.emptyTree(feePerTree: 0x0f_016c)])

        let result = try await ShieldedPool.treeFee(of: [7], using: SolanaRPC(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(result == 0x0f_016c)
        #expect(requests.map { $0["method"] as? String } == ["getMultipleAccounts"])
        #expect(requests.first.flatMap { ($0["params"] as? [Any])?.first as? [String] } == ["2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7"])
    }

    @Test
    func `The fees of several trees add up from one read`() async throws {
        let transport = Self.transport(returning: [UTXOTrees.emptyTree(feePerTree: 5_000), UTXOTrees.emptyTree(feePerTree: 7)])

        let result = try await ShieldedPool.treeFee(of: [0, 1], using: SolanaRPC(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(result == 5_007)
        #expect(requests.map { (($0["params"] as? [Any])?.first as? [String])?.count } == [2])
    }

    @Test
    func `Fees above the program's cap fail`() async throws {
        let transport = Self.transport(returning: [UTXOTrees.emptyTree(feePerTree: 1_000_001)])

        await #expect(throws: ShieldedPool.TreeError.invalidFee) {
            try await ShieldedPool.treeFee(of: [0], using: SolanaRPC(network: .devnet, transport: transport))
        }
    }

    @Test
    func `Accounts shorter than a tree account fail`() async throws {
        let transport = Self.transport(returning: [
            AccountReplies.account(owner: ShieldedPool.programID, data: [UInt8](repeating: 0, count: 16)),
        ])

        await #expect(throws: ShieldedPool.TreeError.invalidLength) {
            try await ShieldedPool.treeFee(of: [0], using: SolanaRPC(network: .devnet, transport: transport))
        }
    }

    static func transport(returning accounts: [String?]) -> StubTransport {
        StubTransport { request in
            try reply(to: request, payload: #""result":\#(AccountReplies.accounts(accounts))"#)
        }
    }
}
