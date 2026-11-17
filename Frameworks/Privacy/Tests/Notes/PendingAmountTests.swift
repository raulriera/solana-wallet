import Foundation
import Testing
@testable import Privacy

struct PendingAmountTests {
    @Test
    func `Amounts without an asset are rejected`() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PendingAmount.self, from: Data(#"{"signature":"a","amount":42}"#.utf8))
        }
    }
}
