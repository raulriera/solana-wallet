import Foundation
import RPC
import Testing

/// Tests Solana's error variants independently of the HTTP client.
struct TransactionErrorTests {
    /// Verifies named variants, instruction failures, and failures carrying account details.
    ///
    /// - Parameters:
    ///   - json: The error's JSON representation.
    ///   - expected: The expected variant and its exact associated data.
    /// - Throws: A decoding error if the fixture isn't a supported transaction error.
    @Test("transaction errors preserve variant names and associated details", arguments: [
        (#""BlockhashNotFound""#, TransactionError(name: "BlockhashNotFound", details: nil)),
        (#"{"InstructionError":[2,"InvalidArgument"]}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(2), .string("InvalidArgument")]))),
        (#"{"InstructionError":[0,{"Custom":4294967295}]}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(4_294_967_295)])]))),
        (#"{"InsufficientFundsForRent":{"account_index":1}}"#,
         TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(1)]))),
    ])
    func transactionErrorsPreserveVariantNamesAndAssociatedDetails(json: String, expected: TransactionError) throws {
        let error = try JSONDecoder().decode(TransactionError.self, from: Data(json.utf8))

        #expect(error == expected)
    }

    /// Verifies that invalid error values can't be interpreted as one transaction failure.
    ///
    /// - Parameter json: An invalid root value or variant object.
    @Test("transaction errors reject malformed variants", arguments: ["null", "42", "[]", "{}", #"{"First":1,"Second":2}"#])
    func transactionErrorsRejectMalformedVariants(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TransactionError.self, from: Data(json.utf8))
        }
    }
}
