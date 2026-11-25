import Foundation
import Testing
@testable import Privacy
@testable import RPC

struct ShieldedAccountRegistrationCostTests {
    static let rent: UInt64 = 1_586_880

    @Test(arguments: [
        (nil, rent),
        (AccountReplies.systemAccount(lamports: 1_000_000), rent - 1_000_000),
        (AccountReplies.systemAccount(lamports: rent), 0),
        (AccountReplies.systemAccount(lamports: rent + 1), 0),
    ] as [(String?, UInt64)])
    func `Costs subtract the record's lamports from its rent`(account: String?, expected: UInt64) async throws {
        let vector = try #require(try RegistryVectors.load().records.first)
        let transport = Self.transport(returning: account)

        let cost = try await TransferVectors.sender().registrationCost(using: SolanaRPC(network: .devnet, transport: transport))

        let requests = await transport.requests
        let methods = try requests.map { try requestBody($0)["method"] as? String }
        let read = try #require(zip(requests, methods).first { $0.1 == "getMultipleAccounts" }?.0)
        #expect(cost == expected)
        #expect(methods.compactMap(\.self).sorted() == ["getMinimumBalanceForRentExemption", "getMultipleAccounts"])
        #expect(try requestedAddresses(read) == [vector.record])
    }

    private static func transport(returning account: String?) -> StubTransport {
        StubTransport { request in
            guard try requestBody(request)["method"] as? String == "getMultipleAccounts" else {
                return try reply(to: request, payload: #""result":\#(rent)"#)
            }
            return try reply(to: request, accounts: [account])
        }
    }
}
