import Foundation
@testable import Privacy
import Testing

/// Verifies pending amounts: their encoding and their redaction.
struct PendingAmountTests {
    /// Verifies that an amount decodes to itself and that both fields are required.
    @Test
    func `Amounts survive encoding and require both fields`() throws {
        let amount = PendingAmount(signature: IndexerResponses.signature(1), lamports: 42)

        let decoded = try JSONDecoder().decode(PendingAmount.self, from: JSONEncoder().encode(amount))

        #expect(decoded == amount)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PendingAmount.self, from: Data(#"{"lamports":42}"#.utf8))
        }
    }

    /// Verifies that printing, dumping, and reflecting an amount omit its values.
    @Test
    func `Amount diagnostics omit the values`() {
        let amount = PendingAmount(signature: IndexerResponses.signature(1), lamports: 42)
        var dumped = ""
        dump(amount, to: &dumped)

        #expect(String(describing: amount) == "PendingAmount")
        #expect(String(reflecting: amount) == "PendingAmount")
        #expect(dumped == "- PendingAmount\n")
    }
}
