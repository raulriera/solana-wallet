import Foundation

/// Why the add-token sheet can't add the pasted text, explained under it.
nonisolated enum TokenRejection: Equatable {
    /// The pasted text isn't an address.
    case notAddress
    /// The token is already in the list.
    case alreadyListed
    /// The address isn't a token mint.
    case notToken
    /// The address is an NFT, which the list can't hold yet.
    case nonFungible

    /// Explains the rejection under the pasted text.
    var message: LocalizedStringResource {
        switch self {
        case .notAddress: "This isn't a valid address."
        case .alreadyListed: "This token is already in your list."
        case .notToken: "This address isn't a token."
        case .nonFungible: "NFTs can't be added yet."
        }
    }
}
