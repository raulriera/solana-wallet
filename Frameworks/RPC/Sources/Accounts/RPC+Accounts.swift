extension RPC {
    /// Reads accounts at one ledger context, in request order.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The earliest slot the response may come from, or `nil` for any slot.
    /// - Returns: Each account's contents, or `nil` where no account exists, with the slot they come from.
    /// - Throws: ``GetMultipleAccountsError/invalidAddressCount`` for no addresses or more than 100,
    ///   ``RPCError/InvalidResponse/mismatchedAccounts`` or ``RPCError/InvalidResponse/staleContext`` if the response
    ///   doesn't match the request, or another RPC error.
    public func accounts(at addresses: [String], minContextSlot: UInt64? = nil) async throws
        -> GetMultipleAccounts.Response {
        try await send(GetMultipleAccounts(addresses: addresses, minContextSlot: minContextSlot))
    }
}
