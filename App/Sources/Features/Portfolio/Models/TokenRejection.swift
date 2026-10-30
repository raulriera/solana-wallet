import Foundation

/// A reason pasted text can't be added as a token.
nonisolated enum TokenRejection: Equatable {
    case notAddress
    case alreadyListed
    case notToken
    case nonFungible

    var message: LocalizedStringResource {
        switch self {
        case .notAddress: "This isn't a valid address."
        case .alreadyListed: "This token is already in your list."
        case .notToken: "This address isn't a token."
        case .nonFungible: "NFTs can't be added yet."
        }
    }
}
