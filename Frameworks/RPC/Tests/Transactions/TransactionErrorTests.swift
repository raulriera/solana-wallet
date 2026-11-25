import Foundation
import RPC
import Testing

struct TransactionErrorTests {
    @Test(arguments: [
        (#""BlockhashNotFound""#, TransactionError(name: "BlockhashNotFound", details: nil)),
        (#"{"InstructionError":[2,"InvalidArgument"]}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(2), .string("InvalidArgument")]))),
        (#"{"InstructionError":[0,{"Custom":4294967295}]}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(4_294_967_295)])]))),
        (#"{"InsufficientFundsForRent":{"account_index":1}}"#,
         TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(1)]))),
    ])
    func `Transaction errors preserve variant names and associated details`(json: String, expected: TransactionError) throws {
        let error = try JSONDecoder().decode(TransactionError.self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(error)

        #expect(error == expected)
        #expect(String(decoding: encoded, as: UTF8.self) == json)
    }

    @Test(arguments: ["null", "42", "[]", "{}", #"{"First":1,"Second":2}"#])
    func `Transaction errors reject malformed variants`(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TransactionError.self, from: Data(json.utf8))
        }
    }
}
