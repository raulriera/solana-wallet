/// A failure to refresh portfolio valuations through the configured price source.
public enum PriceError: Error, Equatable {
    /// A price-only refresh requires an injected price provider.
    case providerUnavailable
    /// Holdings must be retrieved before their prices can be refreshed independently.
    case holdingsUnavailable
    /// The price provider and the holdings refer to different networks.
    case networkMismatch
    /// A provider returned an invalid price, currency, or retrieval time.
    case invalidQuote
}
