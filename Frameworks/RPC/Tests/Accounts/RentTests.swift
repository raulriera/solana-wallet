import Foundation
import RPC
import Testing

/// Verifies the rent request's wire contract.
struct RentTests {
    /// Verifies rent is queried for the specified size and explicit commitment only.
    @Test
    func `Rent queries encode the allocation size and finalized commitment`() throws {
        let request = GetMinimumBalanceForRentExemption(dataLength: 182)
        let parameters = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [Any])

        #expect(parameters.count == 2)
        #expect(parameters.first as? UInt64 == 182)
        #expect(parameters.last as? [String: String] == ["commitment": "finalized"])
    }
}
