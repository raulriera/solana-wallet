import Algorithms
public import Foundation

/// A provider that hosts copies of token logos on its own HTTPS image server.
public protocol LogoProviding: Sendable {
    /// Looks up the provider's copies of token logos.
    ///
    /// - Parameter mints: At most 50 mint addresses on the provider's network.
    /// - Returns: HTTPS logo URLs keyed by mint address.
    /// - Throws: ``LogoError/tooManyMints`` for more than 50 mints, an ``RPCError``, or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL]
}

extension LogoProviding where Self: RPC {
    /// Looks up the provider's copies of token logos with one DAS asset batch.
    ///
    /// - Parameter mints: At most 50 mint addresses on the provider's network.
    /// - Returns: HTTPS logo URLs keyed by mint address.
    /// - Throws: ``LogoError/tooManyMints`` for more than 50 mints, an ``RPCError``, or `CancellationError`.
    public func logos(for mints: [String]) async throws -> [String: URL] {
        guard !mints.isEmpty else { return [:] }
        guard mints.count <= 50 else { throw LogoError.tooManyMints }
        let unique = Array(mints.uniqued())
        let requested = Set(unique)
        var logos: [String: URL] = [:]
        for case let asset? in try await send(GetAssetBatch(ids: unique)) where requested.contains(asset.id) {
            logos[asset.id] = asset.imageURL
        }
        return logos
    }
}
