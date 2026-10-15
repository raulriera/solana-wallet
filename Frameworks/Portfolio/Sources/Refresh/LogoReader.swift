import Foundation
import RPC

/// Finds a provider's logo copies for an account's listed tokens.
struct LogoReader: Sendable {
    let provider: any LogoProviding

    /// Returns the listed tokens' logos, looking up only the tokens that don't have one yet.
    ///
    /// Each token keeps the logo the cached snapshot shows. One lookup asks for the others. A failed
    /// lookup leaves them without a logo, so the next balance read asks again. Native SOL has no lookup.
    /// - Parameters:
    ///   - holdings: The holdings that the balance read returns.
    ///   - cached: The account's previous complete snapshot, if any.
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
        // A logo is decoration: a failure must not fail the balances it accompanies.
        if !missing.isEmpty, let found = try? await provider.logos(for: missing) {
            logos.merge(found) { kept, _ in kept }
        }
        return logos
    }
}

extension Snapshot {
    /// Returns the same holdings with each listed token's logo replaced.
    ///
    /// - Parameter logos: Logo URLs keyed by mint; a token without an entry has no logo.
    /// - Returns: A snapshot that differs only in its listed tokens' logos.
    func replacingLogos(with logos: [String: URL]) -> Snapshot {
        var snapshot = self
        for index in snapshot.holdings.indices {
            guard case .asset(let mint) = snapshot.holdings[index].id else { continue }
            snapshot.holdings[index].imageURL = logos[mint]
        }
        return snapshot
    }
}
