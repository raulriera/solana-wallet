import Observation
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioObservationTests {
    @Test
    func `An inactive scene observes only once it's active`() async throws {
        let shown = ShownWallet(try Account.fixture(index: 1), phase: .inactive)
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        #expect(await window.service.calls.isEmpty)

        shown.phase = .active

        var requests = window.service.requests.makeAsyncIterator()
        let observation = try #require(await requests.next())
        #expect(observation.kind == .observation)
        #expect(observation.owner == shown.account.address.value)
    }

    @Test
    func `Another network observes the wallet there instead`() async throws {
        let account = try Account.fixture(index: 1)
        try await expectReplacedObservation(of: account) { $0.network = .mainnet }
    }

    @Test
    func `Another account observes its own wallet instead`() async throws {
        let other = try Account.fixture(index: 2)
        try await expectReplacedObservation(of: other) { $0.account = other }
    }

    @Test
    func `A settled transaction reads the balances again`() async throws {
        let account = try Account.fixture(index: 1)
        let sent = try PendingPayment(from: account.id)
        let window = try await Window(showing: ShownWallet(account), transactions: sent.transactions)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        _ = try #require(await requests.next())
        #expect(await window.service.calls.map(\.kind) == [.observation])

        #expect(try await sent.settle() == .succeeded)

        let reload = try #require(await requests.next())
        #expect(reload.kind == .reload)
        #expect(reload.owner == account.address.value)
    }

    private func expectReplacedObservation(of account: widgets.Account,
                                           after change: (ShownWallet) -> Void) async throws {
        let shown = ShownWallet(try Account.fixture(index: 1))
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        let first = try #require(await requests.next())

        change(shown)

        for await _ in first.termination {}
        let replacement = try #require(await requests.next())
        #expect(replacement.kind == .observation)
        #expect(replacement.owner == account.address.value)
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
