/// A reason a pasted address can't become a listed token.
public enum TokenLookupError: Error, Equatable {
    /// The address isn't a Token or Token-2022 mint on the portfolio's network.
    case notToken
    /// The mint describes an NFT, which the token list doesn't hold.
    case nonFungible
}
