import Observation
import Portfolio
import Transactions
@testable import widgets

/// Answers lookups and records observations and added and removed tokens in place of the window's portfolio, without
/// any request.
@MainActor
@Observable
final class RecordingPortfolio: PortfolioCoordinating {
    var holdings: [Holding] = []
    var preview: TokenPreview?
    var lookupError: (any Error)?
    var addError: (any Error)?
    var removeError: (any Error)?
    /// Whether each lookup waits for ``releaseLookups()``, so a test can paste again while one runs.
    var holdsLookups = false
    /// Whether each removal waits for ``releaseRemovals()``, so a test can act while one saves.
    var holdsRemovals = false
    /// Reports each lookup that starts waiting.
    let heldLookups: AsyncStream<Void>
    private let heldLookup: AsyncStream<Void>.Continuation
    /// Reports each removal that starts waiting.
    let heldRemovals: AsyncStream<Void>
    private let heldRemoval: AsyncStream<Void>.Continuation
    @ObservationIgnored private var waitingLookups: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var waitingRemovals: [CheckedContinuation<Void, Never>] = []
    private(set) var lookups: [Address] = []
    private(set) var added: [ListedToken] = []
    private(set) var removed: [Address] = []
    /// The wallets that active scenes observed, in order.
    private(set) var observedOwners: [String?] = []
    /// Whether an active scene's task is observing.
    private(set) var isObserving = false

    /// Starts with no tokens, previews, observations, or failures.
    init() {
        (heldLookups, heldLookup) = AsyncStream<Void>.makeStream()
        (heldRemovals, heldRemoval) = AsyncStream<Void>.makeStream()
    }

    var update: Update? { nil }
    var error: PortfolioError?

    /// Records an active scene's observation, which lasts until the view task is cancelled, as the window's
    /// portfolio's does.
    /// - Parameters:
    ///   - owner: The selected wallet.
    ///   - isActive: Whether the scene is active.
    func observe(for owner: String?, isActive: Bool) async {
        guard isActive else { return }
        observedOwners.append(owner)
        isObserving = true
        // Nothing resumes the suspension, so observation ends only when the view task is cancelled.
        await Suspension().suspend()
        isObserving = false
    }

    /// Ignores refreshes, which token workflows never start.
    func refresh() async {}

    /// Answers a lookup with the configured preview or error, once released when lookups are held.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The configured preview.
    /// - Throws: The configured error, or `TokenLookupError.notToken` without a preview.
    func token(at mint: Address) async throws -> TokenPreview {
        lookups.append(mint)
        if holdsLookups {
            await withCheckedContinuation { waitingLookups.append($0); heldLookup.yield() }
        }
        if let lookupError { throw lookupError }
        guard let preview else { throw TokenLookupError.notToken }
        return preview
    }

    /// Lets every waiting lookup finish.
    func releaseLookups() {
        for lookup in waitingLookups { lookup.resume() }
        waitingLookups.removeAll()
    }

    /// Records an added token, or fails with the configured error.
    /// - Parameter token: The token to add.
    /// - Throws: The configured error.
    func add(_ token: ListedToken) async throws {
        if let addError { throw addError }
        added.append(token)
    }

    /// Records a removed token once released when removals are held, or fails with the configured error.
    /// - Parameter mint: The mint address of the token to remove.
    /// - Throws: The configured error.
    func remove(_ mint: Address) async throws {
        if holdsRemovals {
            await withCheckedContinuation { waitingRemovals.append($0); heldRemoval.yield() }
        }
        if let removeError { throw removeError }
        removed.append(mint)
    }

    /// Lets every waiting removal finish.
    func releaseRemovals() {
        for removal in waitingRemovals { removal.resume() }
        waitingRemovals.removeAll()
    }
}
