import RPC
import Transactions

extension RPC {
    /// Reads accounts at one ledger context, in request order.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The earliest acceptable balance observation, or `nil`.
    /// - Returns: Each account's contents, or `nil` where no account exists.
    /// - Throws: A validation or RPC error, or ``AccountReadError/mismatchedResponse`` when the provider
    ///   returns a different number of accounts, or ``AccountReadError/staleContext`` for an older observation.
    func accounts(at addresses: [Address], minContextSlot: UInt64? = nil) async throws -> [Account?] {
        let response = try await send(GetMultipleAccounts(addresses: addresses.map(\.value), minContextSlot: minContextSlot))
        if let minContextSlot, response.context.slot < minContextSlot { throw AccountReadError.staleContext }
        guard response.value.count == addresses.count else { throw AccountReadError.mismatchedResponse }
        return response.value
    }
}

/// A provider response that doesn't match its account read.
enum AccountReadError: Error, Equatable {
    /// The provider returned a different number of accounts than the request asked for.
    case mismatchedResponse
    /// The provider returned balances from before the required finalized change.
    case staleContext
}
