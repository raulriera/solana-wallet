import Foundation
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct ShieldedPoolTreeAccountTests {
    private typealias Fixture = ShieldedPoolTreeFeeTests

    private static var trees: [Address] {
        get throws {
            try ["2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7", "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor"].map(Address.init)
        }
    }

    @Test
    func `Tree accounts are read with one request in the trees' order`() async throws {
        let accounts = [Fixture.account(owner: Fixture.program, data: Self.data(7)), Fixture.account(owner: Fixture.program, data: Self.data(0))]
        let transport = Fixture.transport(returning: accounts.joined(separator: ","))

        let data = try await ShieldedPool.treeAccountData(at: try Self.trees, using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        #expect(data == [Self.data(7), Self.data(0)])
        #expect(requests.map { $0["method"] as? String } == ["getMultipleAccounts"])
        #expect(requests.first.flatMap { ($0["params"] as? [Any])?.first as? [String] } == [
            "2jBVxLnY4tDYJqV34EptnNkXQJtB1yuDfW3mYiApaUa7", "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor",
        ])
    }

    @Test(arguments: [
        ("\(Fixture.account(owner: Fixture.program, data: data(7))),null", ShieldedPool.TreeError.missingTree),
        ("\(Fixture.account(owner: Fixture.program, data: data(7))),\(Fixture.account(owner: "11111111111111111111111111111111", data: data(0)))",
         .foreignOwner),
        (Fixture.account(owner: Fixture.program, data: data(7)), .mismatchedResponse),
        ("null,null,null", .mismatchedResponse),
        ("\(Fixture.account(owner: Fixture.program, data: data(7))),\(Fixture.account(owner: Fixture.program, data: Array(data(0).dropLast())))",
         .invalidLength),
        ("\(Fixture.account(owner: Fixture.program, data: data(7) + [0])),\(Fixture.account(owner: Fixture.program, data: data(0)))",
         .invalidLength),
    ])
    func `Accounts that aren't the trees fail`(accounts: String, error: ShieldedPool.TreeError) async {
        let transport = Fixture.transport(returning: accounts)

        await #expect(throws: error) {
            try await ShieldedPool.treeAccountData(at: try Self.trees, using: Solana(network: .devnet, transport: transport))
        }
    }

    private static func data(_ first: UInt8) -> [UInt8] {
        [first] + [UInt8](repeating: 0, count: 40_079)
    }
}
