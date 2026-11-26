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

    @Test(arguments: ["not Base64", "AAAA"])
    func `Decoding rejects text that isn't a Base64 V1 transaction`(_ text: String) throws {
        let data = try JSONEncoder().encode(text)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Transaction.self, from: data) }
    }
}
