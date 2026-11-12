import Foundation
@testable import Privacy
import Testing

struct PendingAmountTests {
    @Test
    func `Amounts survive encoding and require their asset`() throws {
        let amount = PendingAmount(signature: IndexerResponses.signature(1), asset: .usdc, amount: 42)

        let decoded = try JSONDecoder().decode(PendingAmount.self, from: JSONEncoder().encode(amount))

        #expect(decoded == amount)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PendingAmount.self, from: Data(#"{"signature":"a","amount":42}"#.utf8))
        }
    }
}
