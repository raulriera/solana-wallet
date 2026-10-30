import Foundation
import RPC

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
    func logos(for holdings: [Holding.Identity], keeping cached: Snapshot?) async -> [String: URL] {
        var logos: [String: URL] = [:]
        for holding in cached?.holdings ?? [] {
            if case .asset(let mint) = holding.id, let logo = holding.imageURL { logos[mint] = logo }
        }
        let missing = holdings.compactMap { holding -> String? in
            guard case .asset(let mint) = holding, logos[mint] == nil else { return nil }
            return mint
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
            guard case .asset(let mint) = snapshot.holdings[index].id else { continue }
            snapshot.holdings[index].imageURL = logos[mint]
        }
        return snapshot
    }
}
