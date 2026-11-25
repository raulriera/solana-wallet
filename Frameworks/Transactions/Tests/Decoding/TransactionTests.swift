import Foundation
import Testing
import Transactions

struct TransactionTests {
    @Test
    func `Transactions encode as their Base64 wire bytes and decode unchanged`() throws {
        let transaction = try TransactionDecoder().decode(base64: DecodingFixture.wire)

        let data = try JSONEncoder().encode(transaction)

        #expect(try JSONDecoder().decode(String.self, from: data) == DecodingFixture.wire)
        #expect(try JSONDecoder().decode(Transaction.self, from: data) == transaction)
    }
}
