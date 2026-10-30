import Foundation
@testable import Privacy
@testable import RPC
import Testing

struct ShieldedAccountRegistrationCostTests {
    static let rent: UInt64 = 1_823_520

    @Test(arguments: [
        ("null", rent),
        (account(lamports: 1_000_000), rent - 1_000_000),
        (account(lamports: rent), 0),
        (account(lamports: rent + 1), 0),
    ] as [(String, UInt64)])
    func `Costs subtract the record's lamports from its rent`(account: String, expected: UInt64) async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = Self.transport(returning: account)

        let cost = try await TransferVectors.sender().registrationCost(using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        let read = try #require(requests.first { $0["method"] as? String == "getMultipleAccounts" })
        #expect(cost == expected)
        #expect(requests.compactMap { $0["method"] as? String }.sorted() == ["getMinimumBalanceForRentExemption", "getMultipleAccounts"])
        #expect((read["params"] as? [Any])?.first as? [String] == [vector.record])
    }

    @Test
    func `Mismatched responses fail`() async throws {
        let transport = Self.transport(returning: "null,null")

        await #expect(throws: UserRegistry.ValidationError.mismatchedResponse) {
            try await TransferVectors.sender().registrationCost(using: Solana(network: .devnet, transport: transport))
        }
    }

    static func account(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    private static func transport(returning accounts: String) -> StubTransport {
        StubTransport { request in
            guard try requestBody(request)["method"] as? String == "getMultipleAccounts" else {
                return try reply(to: request, payload: #""result":\#(rent)"#)
            }
            return try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(accounts)]}"#)
        }
    }
}
