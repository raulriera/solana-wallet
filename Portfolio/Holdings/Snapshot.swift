public import Foundation
public import RPC

/// A complete portfolio retrieval for one wallet and network.
public struct Snapshot: Codable, Sendable, Equatable {
    /// The wallet whose holdings were retrieved.
    public let owner: String
    /// The network to which these holdings belong.
    public let network: Network
    /// The wallet's holdings, including a separate native SOL entry.
    public let holdings: [Holding]
    /// The time at which retrieval of every holdings page completed; price-only updates preserve it.
    public let fetchedAt: Date
    /// Completion time of the last successful independent price lookup, including unavailable quotes.
    ///
    /// This records that prices were checked, not that every asset has a price. Older
    /// snapshots and snapshots using only DAS valuations have no independent price time.
    public let pricesFetchedAt: Date?
    /// The lowest indexing watermark across all pages, or `nil` if any page omits it.
    ///
    /// This watermark describes indexing progress; the pages aren't an atomic ledger snapshot.
    public let lastIndexedSlot: UInt64?

    /// The sum of known holding values, kept separate for each quote currency.
    ///
    /// Consult ``unpricedHoldingCount`` before presenting these sums as complete totals.
    /// - Complexity: O(n), where n is the number of holdings.
    public var knownValuesByCurrency: [String: Decimal] {
        holdings.reduce(into: [:]) { totals, holding in
            guard let value = holding.valuation?.total,
                  let currency = holding.valuation?.currency, !currency.isEmpty else { return }
            totals[currency, default: 0] += value
        }
    }

    /// The number of holdings without both a total value and a quote currency.
    ///
    /// - Complexity: O(n), where n is the number of holdings.
    public var unpricedHoldingCount: Int {
        holdings.count { $0.valuation?.total == nil || $0.valuation?.currency?.isEmpty != false }
    }

    /// Creates a portfolio snapshot for a wallet and network.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - network: The Solana network.
    ///   - holdings: The holdings retrieved from all DAS pages.
    ///   - fetchedAt: The successful retrieval time.
    ///   - lastIndexedSlot: The common indexing watermark, or `nil` if unknown.
    ///   - pricesFetchedAt: Completion of the independent price lookup, or `nil` if not performed.
    public init(owner: String, network: Network, holdings: [Holding], fetchedAt: Date, lastIndexedSlot: UInt64?,
                pricesFetchedAt: Date? = nil) {
        self.owner = owner
        self.network = network
        self.holdings = holdings
        self.fetchedAt = fetchedAt
        self.pricesFetchedAt = pricesFetchedAt
        self.lastIndexedSlot = lastIndexedSlot
    }
}
