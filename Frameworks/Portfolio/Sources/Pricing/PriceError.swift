/// A failure to refresh portfolio valuations through the configured price source.
public enum PriceError: Error, Equatable {
    /// The price provider and the holdings refer to different networks.
    case networkMismatch
    /// A provider returned an invalid price, currency, or retrieval time.
    case invalidQuote
}
