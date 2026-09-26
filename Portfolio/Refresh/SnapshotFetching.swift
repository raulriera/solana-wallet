import Foundation
import RPC

/// A type that assembles a complete portfolio from a network source.
protocol SnapshotFetching: Sendable {
    /// The network queried by the source.
    var network: Network { get }

    /// Retrieves every page of a wallet's holdings.
    ///
    /// - Parameter owner: The wallet address to query.
    /// - Returns: A complete portfolio snapshot.
    /// - Throws: A cancellation, RPC, or pagination error.
    func snapshot(for owner: String) async throws -> Snapshot
}

/// A source that assembles portfolio snapshots exclusively from DAS.
struct SnapshotFetcher: SnapshotFetching {
    let rpc: any RPC
    let pageSize: Int
    var network: Network { rpc.network }

    /// Retrieves DAS pages and maps their assets into portfolio holdings.
    ///
    /// - Parameter owner: The wallet address to query.
    /// - Returns: The complete holdings and their indexing information.
    /// - Throws: A cancellation or RPC error, or an invalid-page error if pagination stalls.
    @concurrent
    func snapshot(for owner: String) async throws -> Snapshot {
        var page = 1
        var holdings: [Holding] = []
        var assetIDs: Set<String> = []
        var indexedSlots: [UInt64] = []
        var hasUnknownIndex = false

        while true {
            try Task.checkCancellation()
            let response = try await rpc.send(GetAssetsByOwner(
                owner: owner, page: page, limit: pageSize, includesNativeBalance: page == 1
            ))
            guard response.page == page, response.limit > 0,
                  response.limit <= pageSize, response.items.count <= response.limit else {
                throw FetchError.invalidPage
            }
            if let slot = response.lastIndexedSlot {
                indexedSlots.append(slot)
            } else {
                hasUnknownIndex = true
            }
            if page == 1 {
                holdings.append(nativeHolding(response.nativeBalance))
            }
            if response.items.isEmpty { break }

            var addedCount = 0
            for asset in response.items where assetIDs.insert(asset.id).inserted {
                holdings.append(holding(for: asset))
                addedCount += 1
            }
            guard addedCount > 0, page < Int.max else { throw FetchError.invalidPage }
            page += 1
        }
        try Task.checkCancellation()
        return Snapshot(owner: owner, network: network, holdings: holdings, fetchedAt: Date(),
                        lastIndexedSlot: hasUnknownIndex ? nil : indexedSlots.min())
    }

    /// Maps a DAS asset to a holding without inventing balances or metadata.
    ///
    /// - Parameter asset: The indexed asset to map.
    /// - Returns: The available portfolio information for the asset.
    private func holding(for asset: Asset) -> Holding {
        let amount: Amount?
        if let units = asset.balance, let decimals = asset.decimals {
            amount = Amount(units: units, decimals: decimals)
        } else {
            amount = nil
        }
        let valuation = asset.price.map {
            Valuation(pricePerUnit: $0.perToken, total: $0.total, currency: $0.currency)
        }
        return Holding(id: .asset(asset.id), amount: amount, name: asset.name, symbol: asset.symbol,
                       imageURL: asset.imageURL, valuation: valuation)
    }

    /// Maps native SOL separately from assets such as wrapped SOL.
    ///
    /// - Parameter balance: The DAS native balance, or `nil` if not supplied.
    /// - Returns: A native SOL holding whose amount remains unknown when absent.
    private func nativeHolding(_ balance: NativeBalance?) -> Holding {
        let amount = balance.map { Amount(units: $0.lamports, decimals: 9) }
        let valuation = balance.map { Valuation(pricePerUnit: $0.pricePerSOL, total: $0.totalPrice, currency: "USD") }
        return Holding(id: .nativeSOL, amount: amount, name: "Solana", symbol: "SOL",
                       imageURL: nil, valuation: valuation)
    }
}

/// A failure that prevents a complete DAS retrieval.
enum FetchError: Error {
    /// A page doesn't match the request or makes no progress through the assets.
    case invalidPage
}
