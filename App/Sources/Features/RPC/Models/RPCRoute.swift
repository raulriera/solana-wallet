/// A screen pushed inside RPC.
nonisolated enum RPCRoute: Hashable, Sendable {
    case customRPCSetup
    case customRPCDetails
    /// The saved API key's details.
    case apiKeyDetails
    /// Entry of a new API key.
    case apiKey(RPCEntryPurpose)
}
