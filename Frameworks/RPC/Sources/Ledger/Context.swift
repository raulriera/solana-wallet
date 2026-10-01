/// The ledger context in which a response was evaluated.
public struct Context: Decodable, Sendable {
    /// The slot at which the node evaluated the request.
    public let slot: UInt64

    /// Creates a ledger context for a response.
    ///
    /// - Parameter slot: The slot at which the node evaluated the request.
    public init(slot: UInt64) {
        self.slot = slot
    }
}
