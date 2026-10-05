import RPC

/// Why the portfolio couldn't load or refresh, classified by what the person can do about it.
nonisolated enum PortfolioFailure: Error, Equatable {
    /// No Helius API key is saved on this device.
    case missingKey
    /// Helius rejected the saved key.
    case invalidKey
    /// A provider is limiting requests; the person decides when to try again.
    case rateLimited
    /// The portfolio couldn't load or refresh for another reason, such as a lost connection.
    case unavailable

    /// Classifies an error reported by a portfolio update.
    /// - Parameter error: The failed update's error, which isn't retained.
    init(_ error: any Error) {
        switch error {
        case HeliusClient.Failure.missingKey: self = .missingKey
        case HeliusClient.Failure.invalidKey: self = .invalidKey
        case RPCError.http(statusCode: 429, retryAfter: _): self = .rateLimited
        default: self = .unavailable
        }
    }

    /// Whether the portfolio can load only after the person enters a new key.
    var requiresProviderSetup: Bool { self == .missingKey || self == .invalidKey }
}
