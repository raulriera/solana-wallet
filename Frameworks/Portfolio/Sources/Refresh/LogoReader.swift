import Foundation
import RPC
import Transactions

/// A service that finds a provider's logo copies for an account's listed tokens.
struct LogoReader: Sendable {
    let provider: any LogoProviding

    /// Returns the listed tokens' logos, looking up only the tokens that don't have one yet, or none when the provider
    /// lacks the logos capability.
    ///
    /// - Parameters:
    ///   - assets: The assets to find logos for.
    ///   - cached: The previous snapshot, whose logos are kept while the provider has the logos capability, or `nil`.
    /// - Returns: The available logos, keyed by asset.
    @concurrent
    func logos(for assets: [Asset.ID], keeping cached: Snapshot?) async -> [Asset.ID: URL] {
        if let capabilities = try? await provider.capabilities, !capabilities.contains(.logos) { return [:] }
        var logos: [Asset.ID: URL] = [:]
        for holding in cached?.holdings ?? [] { logos[holding.id] = holding.imageURL }
        let missing = assets.compactMap { asset -> Address? in
            guard case .token(let mint) = asset, logos[asset] == nil else { return nil }
            return mint
        }
        if !missing.isEmpty, let found = try? await provider.logos(for: missing.map(\.value)) {
            for mint in missing { logos[.token(mint: mint)] = found[mint.value] }
        }
        return logos
    }
}

extension Snapshot {
    /// Returns a copy of the snapshot with each listed token's logo replaced.
    ///
    /// - Parameter logos: Logo URLs keyed by asset, where a missing asset means no logo.
    /// - Returns: The snapshot with the new logos.
    func replacingLogos(with logos: [Asset.ID: URL]) -> Snapshot {
        var snapshot = self
        for index in snapshot.holdings.indices {
            snapshot.holdings[index].imageURL = logos[snapshot.holdings[index].id]
        }
        return snapshot
    }
}
