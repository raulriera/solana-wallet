import Observation
import Portfolio
import Transactions

/// The portfolio presentation's lifetime and explicit refresh boundary.
@MainActor
protocol PortfolioCoordinating: AnyObject, Observable {
    /// The selected wallet's latest state, or `nil` before any data is available.
    var update: Update? { get }
    /// The latest snapshot's holdings in display order, or none without a snapshot.
    var holdings: [Holding] { get }
    /// Why the latest update failed, or `nil` when it didn't.
    var error: PortfolioError? { get }

    /// Observes the selected wallet for the lifetime of the calling view task.
    ///
    /// Restart it whenever the wallet, scene activity, or provider connection changes. Cancellation,
    /// an inactive scene, or a replacement wallet stops observation and manual refreshes.
    /// - Parameters:
    ///   - owner: The selected public address, or `nil` when no wallet is selected.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for owner: String?, isActive: Bool) async

    /// Reloads the active wallet, awaiting completion for pull-to-refresh.
    ///
    /// Overlapping calls share one operation, and a disconnected observation connects again.
    /// Cancelling any call cancels that shared operation for every caller; the finalized-change observation
    /// remains active.
    /// Inactive calls do nothing.
    func refresh() async

    /// Looks up a pasted mint address, so the person can check the token before adding it.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: `TokenLookupError` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address) async throws -> TokenPreview

    /// Adds a token to the selected wallet's list; its balance arrives with the next snapshot.
    /// - Parameter token: A token that ``token(at:)`` found.
    /// - Throws: `TokenListError` for a full or unreadable list, or a file-system error if the list can't be saved.
    func add(_ token: ListedToken) async throws

    /// Removes a token from the selected wallet's list; it leaves ``holdings`` with the next snapshot.
    ///
    /// Native SOL has no mint address, so it always stays.
    /// - Parameter mint: The mint address of a listed token.
    /// - Throws: `TokenListError.unreadable` for an unreadable list, or a file-system error if the list can't be saved.
    func remove(_ mint: Address) async throws
}
