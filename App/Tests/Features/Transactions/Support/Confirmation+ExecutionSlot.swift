import RPC
import Testing
@testable import widgets

extension widgets.Confirmation {
    /// Reads the slot in which the transaction executed, so that later reads can include its effects.
    ///
    /// A watch that a landing notification settles doesn't report the slot; a status read supplies it.
    /// - Parameter rpc: The provider whose later reads wait for the slot.
    /// - Returns: The execution slot.
    /// - Throws: An RPC error, or a test failure when the provider doesn't report the transaction.
    func executionSlot(through rpc: any RPC) async throws -> UInt64 {
        if let slot { return slot }
        let response = try await rpc.send(GetSignatureStatuses(signatures: [submission.signature]))
        return try #require(response.value.first ?? nil, "The provider doesn't report the confirmed transaction").slot
    }
}
