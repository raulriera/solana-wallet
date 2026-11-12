/// A response that a node evaluated at one ledger context.
protocol ContextualResponse {
    /// The ledger context in which the node evaluated the request.
    var context: Context { get }
}

/// A request that a node evaluates no earlier than a minimum slot.
protocol ContextualRequest: RPCRequest where Response: ContextualResponse {
    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    var minContextSlot: UInt64? { get }
}

extension ContextualRequest {
    /// Checks that the response comes from the minimum slot or later.
    ///
    /// - Parameter response: The decoded response.
    /// - Throws: ``RPCError/InvalidResponse/staleContext`` if the response comes from an earlier slot.
    public func validate(_ response: Response) throws {
        try LedgerConfiguration(minContextSlot: minContextSlot).validate(contextSlot: response.context.slot)
    }
}
