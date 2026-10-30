/// An error from looking up a token by its mint address.
public enum TokenLookupError: Error, Equatable {
    /// The address isn't a token mint on the portfolio's network.
    case notToken
    case nonFungible
}
