import Foundation
import RPC
import Transactions

/// A service that finds a provider's logo copies for an account's listed tokens.
struct LogoReader: Sendable {
    let provider: any LogoProviding

    /// Returns the listed tokens' logos, looking up only the tokens that don't have one yet.
    ///
    /// - Parameters:
    ///   - holdings: The holdings to find logos for.
    ///   - cached: The previous snapshot, whose logos are kept, or `nil`.
    /// - Returns: The available logos, keyed by mint.
    @concurrent
    func logos(for holdings: [Asset.ID], keeping cached: Snapshot?) async -> [String: URL] {
        var logos: [String: URL] = [:]
        for holding in cached?.holdings ?? [] {
            if case .token(let mint) = holding.id, let logo = holding.imageURL { logos[mint.value] = logo }
        }
        let missing = holdings.compactMap { holding -> String? in
            guard case .token(let mint) = holding, logos[mint.value] == nil else { return nil }
            return mint.value
        }
        if !missing.isEmpty, let found = try? await provider.logos(for: missing) {
            logos.merge(found) { kept, _ in kept }
        }
        return logos
    }
}

extension Snapshot {
    /// Returns a copy of the snapshot with each listed token's logo replaced.
    ///
    /// - Parameter logos: Logo URLs keyed by mint, where a missing mint means no logo.
    /// - Returns: The snapshot with the new logos.
    func replacingLogos(with logos: [String: URL]) -> Snapshot {
        var snapshot = self
        for index in snapshot.holdings.indices {
            guard case .token(let mint) = snapshot.holdings[index].id else { continue }
            snapshot.holdings[index].imageURL = logos[mint.value]
        }
        return snapshot
    }
}
