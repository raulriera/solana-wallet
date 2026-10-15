import Foundation
import Testing
@testable import RPC

/// Verifies simulation balance decoding independently of execution diagnostics.
struct SimulationBalanceTests {
    private static let mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    /// Verifies lamport and token balances decode in account order, with optional attribution fields.
    @Test
    func `Simulation returns lamport and token balances before and after execution`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":{"err":null,"logs":[],"unitsConsumed":450,"fee":5000,
                    "preBalances":[1000000,0,1],"postBalances":[994999,1,1],
                    "preTokenBalances":[{"accountIndex":1,"mint":"\#(Self.mint)","owner":"9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
                        "programId":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                        "uiTokenAmount":{"amount":"18446744073709551615","decimals":6,"uiAmount":null,"uiAmountString":"18446744073709.551615"}}],
                    "postTokenBalances":[{"accountIndex":1,"mint":"\#(Self.mint)","uiTokenAmount":{"amount":"0","decimals":6,"uiAmount":0.0,"uiAmountString":"0"}}]
                }}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let value = try await rpc.send(SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]))).value

        #expect(value.preBalances == [1_000_000, 0, 1])
        #expect(value.postBalances == [994_999, 1, 1])
        #expect(value.preTokenBalances == [SimulateTransaction.TokenBalance(
            accountIndex: 1, mint: Self.mint, owner: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
            amount: .max, decimals: 6
        )])
        #expect(value.postTokenBalances == [SimulateTransaction.TokenBalance(
            accountIndex: 1, mint: Self.mint, owner: nil, amount: 0, decimals: 6
        )])
    }

    /// Verifies omitted or null balances stay unknown instead of becoming empty.
    ///
    /// - Parameter value: The execution outcome without usable balances.
    @Test(arguments: [
        #"{"err":null,"logs":[]}"#,
        #"{"err":null,"preBalances":null,"postBalances":null,"preTokenBalances":null,"postTokenBalances":null}"#,
    ])
    func `Simulation without balances leaves them unknown`(value: String) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":\#(value)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let result = try await rpc.send(SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00]))).value

        #expect(result.preBalances == nil)
        #expect(result.postBalances == nil)
        #expect(result.preTokenBalances == nil)
        #expect(result.postTokenBalances == nil)
    }

    /// Verifies a raw amount that isn't a whole number of units can't decode as zero or truncated units.
    ///
    /// - Parameter amount: The node's raw amount field.
    @Test(arguments: [#""1.5""#, #""-1""#, #""18446744073709551616""#, #""""#, "7"])
    func `Simulation rejects token balances without an integer raw amount`(amount: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":{"err":null,"preTokenBalances":[],"postTokenBalances":[
                    {"accountIndex":1,"mint":"\#(Self.mint)","uiTokenAmount":{"amount":\#(amount),"decimals":6,"uiAmountString":"0"}}
                ]}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(SimulateTransaction(transaction: Data([0x81, 0xFB, 0xFF, 0x00])))
        }
    }
}
