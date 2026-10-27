import Foundation
import Portfolio
import Testing
import Transactions

/// Controls portfolio workflow events without substituting an RPC client.
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
    private let registration: Registration?

    /// Creates isolated events, optionally suspending observation registration.
    /// - Parameter registration: A deliberately cancellation-insensitive setup gate.
    init(registration: Registration? = nil) {
        (requests, requested) = AsyncStream<Request>.makeStream()
        self.registration = registration
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
    /// Reports token-list edits during view lifecycle changes.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The requested wallet.
    /// - Throws: An unreadable-list error.
    func addToken(_ token: ListedToken, for owner: String) async throws {
        Issue.record("Lifecycle coordination must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports token-list edits during view lifecycle changes.
    /// - Parameters:
    ///   - mint: The token to remove.
    ///   - owner: The requested wallet.
    /// - Throws: An unreadable-list error.
    func removeToken(_ mint: Address, for owner: String) async throws {
        Issue.record("Lifecycle coordination must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports token lookups during view lifecycle changes.
    /// - Parameter mint: The requested mint address.
    /// - Returns: Nothing; the lookup always fails.
    /// - Throws: A not-a-token error.
    func token(at mint: Address) async throws -> TokenPreview {
        Issue.record("Lifecycle coordination must not look up tokens.")
        throw TokenLookupError.notToken
    }
}
