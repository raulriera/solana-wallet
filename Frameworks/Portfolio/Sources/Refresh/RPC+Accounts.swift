import RPC
import Transactions

extension RPC {
    /// Reads accounts at one ledger context, in request order.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The earliest slot the response may come from, or `nil` for any slot.
    /// - Returns: Each account's contents, or `nil` where no account exists.
    /// - Throws: A validation or RPC error, or an ``AccountReadError``.
    func accounts(at addresses: [Address], minContextSlot: UInt64? = nil) async throws -> [Account?] {
        let response = try await send(GetMultipleAccounts(addresses: addresses.map(\.value), minContextSlot: minContextSlot))
        if let minContextSlot, response.context.slot < minContextSlot { throw AccountReadError.staleContext }
        guard response.value.count == addresses.count else { throw AccountReadError.mismatchedResponse }
        return response.value
    }
}

/// An error from an account read whose response doesn't match the request.
enum AccountReadError: Error, Equatable {
    /// The response holds a different number of accounts than requested.
    case mismatchedResponse
    /// The response comes from a slot before the minimum context slot.
    case staleContext
}
