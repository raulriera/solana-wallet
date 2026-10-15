/// A failure to refresh portfolio valuations through the configured price source.
public enum PriceError: Error, Equatable {
    /// A provider returned an invalid price or currency.
    case invalidQuote
}
