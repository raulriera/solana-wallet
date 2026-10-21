import Foundation
@testable import Privacy
@testable import RPC
import Testing

/// Verifies an account's registration cost through a real RPC client with local responses: the
/// record's rent less the lamports at the sender's independently derived record address.
struct ShieldedAccountRegistrationCostTests {
    /// The rent of a 134-byte record that the responses report.
    static let rent: UInt64 = 1_823_520

    /// Verifies the cost for a record address that holds no account, some lamports, the whole rent,
    /// and more than the rent, with one rent read and one `getMultipleAccounts` read of the record.
    ///
    /// - Parameters:
    ///   - account: The account at the record's address, as JSON.
    ///   - expected: The expected cost.
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

    /// Verifies that a response of another length fails the read.
    @Test
    func `Mismatched responses fail`() async throws {
        let transport = Self.transport(returning: "null,null")

        await #expect(throws: UserRegistry.ValidationError.mismatchedResponse) {
            try await TransferVectors.sender().registrationCost(using: Solana(network: .devnet, transport: transport))
        }
    }

    /// Creates the JSON of a System Program account without data.
    ///
    /// - Parameter lamports: The account's balance.
    /// - Returns: The account's JSON object.
    static func account(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    /// Creates a transport that answers the rent read with ``rent`` and every `getMultipleAccounts`
    /// read with the given accounts.
    ///
    /// - Parameter accounts: The accounts' JSON, separated by commas.
    /// - Returns: The transport.
    private static func transport(returning accounts: String) -> StubTransport {
        StubTransport { request in
            guard try requestBody(request)["method"] as? String == "getMultipleAccounts" else {
                return try reply(to: request, payload: #""result":\#(rent)"#)
            }
            return try reply(to: request, payload: #""result":{"context":{"slot":7},"value":[\#(accounts)]}"#)
        }
    }
}
