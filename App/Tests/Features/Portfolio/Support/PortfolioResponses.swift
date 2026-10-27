import Foundation
import Portfolio
import Testing
import Transactions

/// Controls portfolio workflow events and token-list answers without substituting an RPC client.
actor PortfolioResponses: PortfolioProviding {
    /// The portfolio operations requested by a presentation.
    enum Kind: Sendable, Equatable {
        case observation
        case refresh
        case reload
    }

    /// A request whose updates and termination can be driven independently.
    struct Request: Sendable {
        let owner: String
        let kind: Kind
        let continuation: AsyncStream<Update>.Continuation
        let termination: AsyncStream<Void>
    }

    nonisolated let requests: AsyncStream<Request>
    private let requested: AsyncStream<Request>.Continuation
    private(set) var calls: [Request] = []
    /// The looked-up mint addresses, in order.
    private(set) var lookups: [Address] = []
    /// The added tokens, in order.
    private(set) var added: [ListedToken] = []
    /// The removed mint addresses, in order.
    private(set) var removed: [Address] = []
    private let registration: Registration?
    private let preview: TokenPreview?
    private let lookupGate: Suspension?
    private let removalGate: Suspension?
    private var lookupError: (any Error)?
    private var addError: (any Error)?
    private var removeError: (any Error)?

    /// Creates isolated events, optionally suspending observation registration, lookups, or removals.
    /// - Parameters:
    ///   - registration: A deliberately cancellation-insensitive setup gate.
    ///   - preview: The token that each lookup finds; without one, a lookup finds no token.
    ///   - lookupGate: A suspension inside the lookup, for a test that pastes again while it runs.
    ///   - removalGate: A suspension inside the removal, for a test that acts while it saves.
    init(registration: Registration? = nil, preview: TokenPreview? = nil, lookupGate: Suspension? = nil,
         removalGate: Suspension? = nil) {
        (requests, requested) = AsyncStream<Request>.makeStream()
        self.registration = registration
        self.preview = preview
        self.lookupGate = lookupGate
        self.removalGate = removalGate
    }

    /// Makes later lookups fail with an error, or succeed again.
    /// - Parameter error: The error that lookups throw, or `nil` to find the preview.
    func failLookups(with error: (any Error)?) {
        lookupError = error
    }

    /// Makes later adds fail with an error, or succeed again.
    /// - Parameter error: The error that adds throw, or `nil` to record the token.
    func failAdds(with error: (any Error)?) {
        addError = error
    }

    /// Makes later removals fail with an error, or succeed again.
    /// - Parameter error: The error that removals throw, or `nil` to record the mint address.
    func failRemovals(with error: (any Error)?) {
        removeError = error
    }

    /// Registers a controllable long-lived observation.
    /// - Parameter owner: The wallet selected by the coordinator.
    /// - Returns: The requested observation's stream.
    func observations(for owner: String) async -> AsyncStream<Update> {
        let stream = makeStream(for: owner, kind: .observation)
        await registration?.wait()
        return stream
    }

    /// Registers a controllable explicit refresh.
    /// - Parameter owner: The wallet selected by the coordinator.
    /// - Returns: The requested refresh's stream.
    func updates(for owner: String) async -> AsyncStream<Update> {
        makeStream(for: owner, kind: .refresh)
    }

    /// Registers a controllable reload, which lasts until the test finishes its stream or the caller is cancelled.
    ///
    /// Updates sent on the reload's stream are dropped; a real reload's results arrive through the observation.
    /// - Parameter owner: The wallet to read again.
    func reload(for owner: String) async {
        for await _ in makeStream(for: owner, kind: .reload) {}
    }

    /// Reports unexpected cache removal during view lifecycle changes.
    /// - Parameter owner: The requested wallet.
    func removeData(for owner: String) async throws {
        Issue.record("Leaving a view must not remove persisted holdings.")
    }

    /// Reports an unexpected provider change during view lifecycle changes.
    func providerDidChange() async throws {
        Issue.record("Lifecycle coordination must not change providers.")
    }

    /// Reports an unexpected price change during view lifecycle changes.
    func pricesDidChange() async {
        Issue.record("Lifecycle coordination must not change prices.")
    }

    /// Captures an operation and reports when cancellation releases its stream.
    /// - Parameters:
    ///   - owner: The requested wallet.
    ///   - kind: The requested operation.
    /// - Returns: The independently controlled stream.
    private func makeStream(for owner: String, kind: Kind) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream()
        let termination = AsyncStream<Void>.makeStream()
        continuation.onTermination = { @Sendable _ in termination.continuation.finish() }
        let request = Request(owner: owner, kind: kind, continuation: continuation,
                              termination: termination.stream)
        calls.append(request)
        requested.yield(request)
        return stream
    }

    /// Holds setup across cancellation to exercise late registration, without sleeps.
    actor Registration {
        private var released = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        /// Waits for an explicit release, deliberately ignoring task cancellation.
        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        /// Allows every current and future registration to complete.
        func release() {
            released = true
            for continuation in waiting { continuation.resume() }
            waiting.removeAll()
        }
    }
}

extension PortfolioResponses: TokenListProviding {
    /// Records an added token, or fails with the set error.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The wallet whose list the token joins.
    /// - Throws: The set error.
    func addToken(_ token: ListedToken, for owner: String) async throws {
        if let addError { throw addError }
        added.append(token)
    }

    /// Records a removed token once the removal gate, if any, is released, or fails with the set error.
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The wallet whose list the token leaves.
    /// - Throws: The set error.
    func removeToken(_ mint: Address, for owner: String) async throws {
        await removalGate?.suspend()
        if let removeError { throw removeError }
        removed.append(mint)
    }

    /// Answers a lookup with the preview or the set error, once the lookup gate, if any, is released.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The preview.
    /// - Throws: The set error, or `TokenLookupError.notToken` without a preview.
    func token(at mint: Address) async throws -> TokenPreview {
        lookups.append(mint)
        await lookupGate?.suspend()
        if let lookupError { throw lookupError }
        guard let preview else { throw TokenLookupError.notToken }
        return preview
    }
}
