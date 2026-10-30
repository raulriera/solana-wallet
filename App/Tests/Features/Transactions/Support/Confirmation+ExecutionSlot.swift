import RPC
import Testing
@testable import widgets

extension widgets.Confirmation {
    func executionSlot(through rpc: any RPC) async throws -> UInt64 {
        if let slot { return slot }
        let response = try await rpc.send(GetSignatureStatuses(signatures: [submission.signature]))
        return try #require(response.value.first ?? nil, "The provider doesn't report the confirmed transaction").slot
    }
}
