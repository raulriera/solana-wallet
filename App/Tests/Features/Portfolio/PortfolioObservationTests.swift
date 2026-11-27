import Observation
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioObservationTests {
    @Test(arguments: [ScenePhase.active, .inactive])
    func `A background scene observes only once it's in the foreground`(phase: ScenePhase) async throws {
        let shown = ShownWallet(try Account.fixture(index: 1), phase: .background)
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        #expect(await window.service.calls.isEmpty)

        shown.phase = phase

        var requests = window.service.requests.makeAsyncIterator()
        let observation = try #require(await requests.next())
        #expect(observation.kind == .observation)
        #expect(observation.owner == shown.account.address.value)
    }

    @Test(arguments: Change.allCases)
    func `Another network or account replaces the observation`(_ change: Change) async throws {
        let shown = ShownWallet(try Account.fixture(index: 1))
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        let first = try #require(await requests.next())

        switch change {
        case .network: shown.network = .mainnet
        case .account: shown.account = try Account.fixture(index: 2)
        }

        for await _ in first.termination {}
        let replacement = try #require(await requests.next())
        #expect(replacement.kind == .observation)
        #expect(replacement.owner == shown.account.address.value)
    }

    @Test
    func `A settled transaction reads the balances again`() async throws {
        let account = try Account.fixture(index: 1)
        let record = TransactionRecord.fixture(.payment, account: account.id)
        let sending = try LocalSending(pending: StoredValue([record]))
        let window = try await Window(showing: ShownWallet(account), transactions: sending.store)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        _ = try #require(await requests.next())
        #expect(await window.service.calls.map(\.kind) == [.observation])

        #expect(try await sending.settle(record) == .succeeded)

        let reload = try #require(await requests.next())
        #expect(reload.kind == .reload)
        #expect(reload.owner == account.address.value)
    }

    enum Change: CaseIterable {
        case network
        case account
    }

    @MainActor
    private struct Window {
        let service = PortfolioResponses()
        let hosted: HostedWindow<PortfolioObservationRoot>

        init(showing shown: ShownWallet, transactions: TransactionStore = .unused) async throws {
            hosted = try HostedWindow(PortfolioObservationRoot(portfolios: .serving(service), shown: shown,
                                                               transactions: transactions))
            try #require(try await hosted.appears())
        }
    }
}
