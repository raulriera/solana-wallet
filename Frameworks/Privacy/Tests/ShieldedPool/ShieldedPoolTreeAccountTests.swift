import Foundation
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct ShieldedPoolTreeAccountTests {
    private static var trees: [Address] {
        get throws {
            try ["2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7", "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor"].map(Address.init)
        }
    }

    @Test
    func `Tree accounts are read with one request in the trees' order`() async throws {
        let transport = StubTransport.replying(accounts: [Self.account(Self.data(7)), Self.account(Self.data(0))])

        let data = try await ShieldedPool.treeAccountData(at: try Self.trees, using: SolanaRPC(network: .devnet, transport: transport))

        #expect(data == [Self.data(7), Self.data(0)])
        #expect(try await transport.requests.map(requestedAddresses) == [[
            "2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7", "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor",
        ]])
    }

    @Test(arguments: [
        ([account(data(7)), nil], ShieldedPool.TreeError.missingTree),
        ([account(data(7)), AccountReplies.account(owner: "11111111111111111111111111111111", data: data(0))], .foreignOwner),
        ([account(data(7)), account(Array(data(0).dropLast()))], .invalidLength),
        ([account(data(7) + [0]), account(data(0))], .invalidLength),
    ] as [([String?], ShieldedPool.TreeError)])
    func `Accounts that aren't the trees fail`(accounts: [String?], error: ShieldedPool.TreeError) async {
        let transport = StubTransport.replying(accounts: accounts)

        await #expect(throws: error) {
            try await ShieldedPool.treeAccountData(at: try Self.trees, using: SolanaRPC(network: .devnet, transport: transport))
        }
    }

    private static func account(_ data: [UInt8]) -> String {
        AccountReplies.account(owner: ShieldedPool.programID, data: data)
    }

    private static func data(_ first: UInt8) -> [UInt8] {
        [first] + [UInt8](repeating: 0, count: 40_079)
    }
}
