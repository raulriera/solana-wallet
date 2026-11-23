import Algorithms
public import Foundation

/// A provider that looks up its copies of token logos on its own HTTPS image server when it has the
/// ``Capabilities/logos`` capability.
public protocol LogoProviding: RPC {
    /// Looks up the provider's copies of token logos.
    ///
    /// - Parameter mints: At most 50 mint addresses on the provider's network.
    /// - Returns: HTTPS logo URLs keyed by mint address.
    /// - Throws: ``LogoError/tooManyMints`` for more than 50 mints, an ``RPCError``, or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL]
}

extension LogoProviding {
    /// Looks up the provider's copies of token logos with one DAS asset batch, or returns none without a request when
    /// the provider lacks the ``Capabilities/logos`` capability.
    ///
    /// - Parameter mints: At most 50 mint addresses on the provider's network.
    /// - Returns: HTTPS logo URLs keyed by mint address.
    /// - Throws: ``LogoError/tooManyMints`` for more than 50 mints, the error of ``RPC/capabilities``, an ``RPCError``,
    ///   or `CancellationError`.
    public func logos(for mints: [String]) async throws -> [String: URL] {
        guard mints.count <= 50 else { throw LogoError.tooManyMints }
        guard !mints.isEmpty, try await capabilities.contains(.logos) else { return [:] }
        return try await assetLogos(for: Array(mints.uniqued()))
    }

    /// Returns the ``Capabilities/logos`` capability when the provider's server serves copies of token logos, whatever
    /// capabilities the client declares.
    ///
    /// - Parameter mint: A mint address whose token has a logo.
    /// - Returns: ``Capabilities/logos`` when the server returns an HTTPS copy of the mint's logo, or no capabilities.
    /// - Throws: A rate-limit ``RPCError``, or `CancellationError`.
    public func logoCapability(checking mint: String) async throws -> Capabilities {
        try await Capabilities(.logos) { try await assetLogos(for: [mint])[mint] != nil }
    }

    /// Looks up the provider's copies of the logos of assets with one DAS asset batch.
    ///
    /// - Parameter ids: Unique asset IDs.
    /// - Returns: HTTPS logo URLs keyed by the requested IDs.
    /// - Throws: An ``RPCError``, or `CancellationError`.
    private func assetLogos(for ids: [String]) async throws -> [String: URL] {
        let requested = Set(ids)
        var logos: [String: URL] = [:]
        for case let asset? in try await send(GetAssetBatch(ids: ids)) where requested.contains(asset.id) {
            logos[asset.id] = asset.imageURL
        }
        return logos
    }
}
