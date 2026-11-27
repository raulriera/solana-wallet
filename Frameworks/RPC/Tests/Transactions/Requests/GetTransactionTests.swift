import Foundation
import Testing
@testable import RPC

struct GetTransactionTests {
    private static let signature = "3wJ4Xie5Q47SYWve2mFC1fbhSdt3bmQ2phV3UssUJkpb6DrazBJ5AaXT3yzPkMkAPDRzA5B3h4PcbPDFwmodSAkZ"

    private static let accountKeys = [
        "QhTvNz2x7d8tVkwd6BFsgqqaQ5oLwTcyg6j7pnvpkik", "777pvSGe5LaBd9nCczvE2FXEauiwtfGJ5XRpjKyniGor",
        "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW", "11111111111111111111111111111111",
    ]

    private static let pool = accountKeys[2]

    private static let system = accountKeys[3]

    private static let writable = "DWLsLesEAYoZvVCxbmsRtSZo6ywpJkFrduUTzAik6e67"

    private static let readonly = "CiNmas621VuyofiDSrEPfTXHKrdZuB6jMKECyNiMpLXE"

    @Test
    func `Transaction reads ask for finalized V1 transactions as JSON and read unknown ones as nil`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":null"#) }
        let rpc = SolanaRPC.devnet(transport: transport)

        let transaction = try await rpc.send(GetTransaction(signature: Self.signature))

        #expect(transaction == nil)
        let body = try requestBody(try #require(await transport.requests.first))
        #expect(body["method"] as? String == "getTransaction")
        let params = try #require(body["params"] as? [Any])
        #expect(params.first as? String == Self.signature)
        let configuration = try #require(params.last as? [String: Any])
        #expect(configuration["commitment"] as? String == "finalized")
        #expect(configuration["encoding"] as? String == "json")
        #expect(configuration["maxSupportedTransactionVersion"] as? Int == 1)
        #expect(configuration.count == 3)
    }

    @Test
    func `A program's instruction data comes from top-level and invoked instructions in execution order`() async throws {
        let instructions = #"[{"programIdIndex":2,"accounts":[0,1,4,5],"data":"Qj99L","stackHeight":1},"#
            + #"{"programIdIndex":3,"accounts":[0,5],"data":"3Bxs4fnbFx59msBM","stackHeight":1},"#
            + #"{"programIdIndex":4,"accounts":[],"data":"","stackHeight":1}]"#
        let inner = #"[{"index":2,"instructions":[{"programIdIndex":2,"accounts":[],"data":"1H","stackHeight":2}]},"#
            + #"{"index":0,"instructions":[{"programIdIndex":5,"accounts":[0],"data":"1","stackHeight":2},"#
            + #"{"programIdIndex":2,"accounts":[],"data":"","stackHeight":3}]}]"#

        let transaction = try #require(try await read(Self.transaction(instructions: instructions, innerInstructions: inner)))

        #expect(transaction.error == nil)
        #expect(transaction.instructionData(invoking: Self.pool) == [Data([16, 1, 2, 3]), Data(), Data([0, 16])])
        #expect(transaction.instructionData(invoking: Self.system) == [Data([2, 0, 0, 0, 232, 191, 17, 0, 0, 0, 0, 0])])
        #expect(transaction.instructionData(invoking: Self.writable) == [Data()])
        #expect(transaction.instructionData(invoking: Self.readonly) == [Data([0])])
        #expect(transaction.instructionData(invoking: Self.accountKeys[0]).isEmpty)
    }

    @Test
    func `Transactions without loaded addresses or recorded invoked instructions read their top-level instructions`() async throws {
        let instructions = #"[{"programIdIndex":2,"accounts":[1,0],"data":"1H"}]"#

        let transaction = try #require(try await read(Self.transaction(instructions: instructions, innerInstructions: "null", loadedAddresses: nil)))

        #expect(transaction.instructionData(invoking: Self.pool) == [Data([0, 16])])
    }

    @Test
    func `Failed transactions keep their error`() async throws {
        let instructions = #"[{"programIdIndex":2,"accounts":[0],"data":"Qj99L"}]"#

        let transaction = try #require(try await read(Self.transaction(error: #"{"InstructionError":[0,{"Custom":6001}]}"#, instructions: instructions)))

        #expect(transaction.error == TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6_001)])])))
        #expect(transaction.instructionData(invoking: Self.pool) == [Data([16, 1, 2, 3])])
    }

    @Test
    func `Other programs' invalid data doesn't fail the read`() async throws {
        let instructions = #"[{"programIdIndex":3,"accounts":[0],"data":"0OIl"},{"programIdIndex":2,"accounts":[0],"data":"Qj99L"}]"#

        let transaction = try #require(try await read(Self.transaction(instructions: instructions)))

        #expect(transaction.instructionData(invoking: Self.pool) == [Data([16, 1, 2, 3])])
        #expect(transaction.instructionData(invoking: Self.system) == [])
    }

    @Test
    func `A program's data that isn't base-58 or is longer than a V1 transaction is left out`() async throws {
        let longest = String(repeating: "1", count: 4_096)
        let instructions = #"[{"programIdIndex":2,"accounts":[],"data":"0OIl"},"#
            + #"{"programIdIndex":2,"accounts":[],"data":"\#(longest)1"},"#
            + #"{"programIdIndex":2,"accounts":[],"data":"\#(longest)"}]"#

        let transaction = try #require(try await read(Self.transaction(instructions: instructions)))

        #expect(transaction.instructionData(invoking: Self.pool) == [Data(count: 4_096)])
    }

    @Test(arguments: [
        (#"[{"programIdIndex":6,"accounts":[0],"data":"Qj99L"}]"#, "[]"),
        (#"[{"programIdIndex":-1,"accounts":[0],"data":"Qj99L"}]"#, "[]"),
        (#"[{"programIdIndex":2,"accounts":[0],"data":"Qj99L"}]"#, #"[{"index":0,"instructions":[{"programIdIndex":6,"data":"1H"}]}]"#),
        (#"[{"programIdIndex":2,"accounts":[0],"data":"Qj99L"}]"#, #"[{"index":1,"instructions":[{"programIdIndex":2,"data":"1H"}]}]"#),
    ])
    func `Instructions that name a missing program or instruction fail to decode`(instructions: String, inner: String) async throws {
        await #expect(throws: RPCError.decoding) {
            try await read(Self.transaction(instructions: instructions, innerInstructions: inner))
        }
    }

    @Test(arguments: [
        #"{"slot":5,"meta":null,"transaction":{"signatures":[],"message":{"accountKeys":[],"instructions":[]}}}"#,
        #"{"slot":5,"meta":{"fee":5000},"transaction":{"signatures":[],"message":{"accountKeys":[],"instructions":[]}}}"#,
    ])
    func `Transactions without status metadata or an execution outcome fail to decode`(transaction: String) async throws {
        await #expect(throws: RPCError.decoding) {
            try await read(transaction)
        }
    }

    @Test
    func `Transaction responses longer than one mebibyte are refused`() async throws {
        let logs = #"[""# + String(repeating: "a", count: 1_048_576) + #""]"#

        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await read(Self.transaction(instructions: "[]", logs: logs))
        }
    }

    private func read(_ result: String) async throws -> GetTransaction.Value? {
        let transport = StubTransport { try reply(to: $0, payload: #""result":\#(result)"#) }
        return try await SolanaRPC.devnet(transport: transport).send(GetTransaction(signature: Self.signature))
    }

    private static func transaction(
        error: String = "null",
        instructions: String,
        innerInstructions: String = "[]",
        loadedAddresses: String? = #"{"writable":["\#(GetTransactionTests.writable)"],"readonly":["\#(GetTransactionTests.readonly)"]}"#,
        logs: String = "[]"
    ) -> String {
        let keys = accountKeys.map { "\"\($0)\"" }.joined(separator: ",")
        let loaded = loadedAddresses.map { #""loadedAddresses":\#($0),"# } ?? ""
        return #"{"blockTime":1793645401,"slot":517950522,"version":1,"meta":{"computeUnitsConsumed":175996,"err":\#(error),"#
            + #""fee":5000,"innerInstructions":\#(innerInstructions),\#(loaded)"logMessages":\#(logs),"#
            + #""postBalances":[1,1,1,1,1,1],"preBalances":[1,1,1,1,1,1],"status":{"Ok":null}},"#
            + #""transaction":{"signatures":["\#(signature)"],"message":{"accountKeys":[\#(keys)],"#
            + #""header":{"numReadonlySignedAccounts":0,"numReadonlyUnsignedAccounts":2,"numRequiredSignatures":1},"#
            + #""instructions":\#(instructions),"recentBlockhash":"ENhz8SWATnHMxVZ1ubBnVDQDhVFb4oZ9Z5phDEALd3bS"}}}"#
    }
}
