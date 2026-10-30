import Foundation
import Portfolio
import Testing
import Transactions

actor PortfolioResponses: PortfolioProviding {
    enum Kind: Sendable, Equatable {
        case observation
        case refresh
        case reload
    }

    struct Request: Sendable {
        let owner: String
        let kind: Kind
        let continuation: AsyncStream<Update>.Continuation
        let termination: AsyncStream<Void>
    }

    nonisolated let requests: AsyncStream<Request>
    private let requested: AsyncStream<Request>.Continuation
    private(set) var calls: [Request] = []
    private(set) var lookups: [Address] = []
    private(set) var added: [ListedToken] = []
    private(set) var removed: [Address] = []
    private let registration: Registration?
    private let preview: TokenPreview?
    private let lookupGate: Suspension?
    private let removalGate: Suspension?
    private var lookupError: (any Error)?
    private var addError: (any Error)?
    private var removeError: (any Error)?

    init(registration: Registration? = nil, preview: TokenPreview? = nil, lookupGate: Suspension? = nil,
         removalGate: Suspension? = nil) {
        (requests, requested) = AsyncStream<Request>.makeStream()
        self.registration = registration
        self.preview = preview
        self.lookupGate = lookupGate
        self.removalGate = removalGate
    }

    func failLookups(with error: (any Error)?) {
        lookupError = error
    }

    func failAdds(with error: (any Error)?) {
        addError = error
    }

    func failRemovals(with error: (any Error)?) {
        removeError = error
    }

    func observations(for owner: String) async -> AsyncStream<Update> {
        let stream = makeStream(for: owner, kind: .observation)
        await registration?.wait()
        return stream
    }

    func updates(for owner: String) async -> AsyncStream<Update> {
        makeStream(for: owner, kind: .refresh)
    }

    func reload(for owner: String) async {
        for await _ in makeStream(for: owner, kind: .reload) {}
    }

    func removeData(for owner: String) async throws {
        Issue.record("Leaving a view must not remove persisted holdings.")
    }

    func providerDidChange() async throws {
        Issue.record("Lifecycle coordination must not change providers.")
    }

    func pricesDidChange() async {
        Issue.record("Lifecycle coordination must not change prices.")
    }

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

    actor Registration {
        private var released = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            released = true
            for continuation in waiting { continuation.resume() }
            waiting.removeAll()
        }
    }
}

extension PortfolioResponses: TokenListProviding {
    func addToken(_ token: ListedToken, for owner: String) async throws {
        if let addError { throw addError }
        added.append(token)
    }

    func removeToken(_ mint: Address, for owner: String) async throws {
        await removalGate?.suspend()
        if let removeError { throw removeError }
        removed.append(mint)
    }

    func token(at mint: Address) async throws -> TokenPreview {
        lookups.append(mint)
        await lookupGate?.suspend()
        if let lookupError { throw lookupError }
        guard let preview else { throw TokenLookupError.notToken }
        return preview
    }
}
