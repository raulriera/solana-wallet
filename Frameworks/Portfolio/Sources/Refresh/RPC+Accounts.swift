import RPC
import Transactions

extension RPC {
    /// Reads accounts at one ledger context, in request order.
    ///
    /// - Parameter addresses: One through 100 account addresses.
    /// - Returns: Each account's contents, or `nil` where no account exists.
    /// - Throws: A validation or RPC error, or ``AccountReadError/mismatchedResponse`` when the provider
    ///   returns a different number of accounts.
    func accounts(at addresses: [Address]) async throws -> [Account?] {
        let response = try await send(GetMultipleAccounts(addresses: addresses.map(\.value)))
        guard response.value.count == addresses.count else { throw AccountReadError.mismatchedResponse }
        return response.value
    }
}

/// A provider response that doesn't match its account read.
enum AccountReadError: Error {
    /// The provider returned a different number of accounts than the request asked for.
    case mismatchedResponse
}
