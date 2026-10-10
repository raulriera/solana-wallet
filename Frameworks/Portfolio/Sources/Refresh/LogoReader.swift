import Foundation
import RPC

/// Adds a provider's logo copies to a balance read's listed tokens.
struct LogoReader: Sendable {
    let provider: any LogoProviding

    /// Returns the balance read with logos, looking up only the tokens that don't have one yet.
    ///
    /// Each token keeps the logo the cached snapshot shows. One lookup asks for the others. A failed
    /// lookup leaves them without a logo, so the next balance read asks again. Native SOL has no lookup.
    /// - Parameters:
    ///   - snapshot: A balance read without logos.
    ///   - cached: The account's previous complete snapshot, if any.
    /// - Returns: The same balances, with the logos that are available.
    @concurrent
    func snapshot(addingLogosTo snapshot: Snapshot, keeping cached: Snapshot?) async -> Snapshot {
        var logos: [String: URL] = [:]
        for holding in cached?.holdings ?? [] {
            if case .asset(let mint) = holding.id, let logo = holding.imageURL { logos[mint] = logo }
        }
        let missing = snapshot.holdings.compactMap { holding -> String? in
            guard case .asset(let mint) = holding.id, logos[mint] == nil else { return nil }
            return mint
        }
        // A logo is decoration: a failure must not fail the balances it accompanies.
        if !missing.isEmpty, let found = try? await provider.logos(for: missing) {
            logos.merge(found) { kept, _ in kept }
        }
        return snapshot.replacingLogos(with: logos)
    }
}

extension Snapshot {
    /// Returns the same holdings with each listed token's logo replaced.
    ///
    /// - Parameter logos: Logo URLs keyed by mint; a token without an entry has no logo.
    /// - Returns: A snapshot that differs only in its listed tokens' logos.
    func replacingLogos(with logos: [String: URL]) -> Snapshot {
        let holdings = self.holdings.map { holding in
            guard case .asset(let mint) = holding.id else { return holding }
            return Holding(id: holding.id, amount: holding.amount, name: holding.name, symbol: holding.symbol,
                           imageURL: logos[mint], valuation: holding.valuation)
        }
        return Snapshot(owner: owner, network: network, holdings: holdings, fetchedAt: fetchedAt,
                        pricesFetchedAt: pricesFetchedAt)
    }
}
