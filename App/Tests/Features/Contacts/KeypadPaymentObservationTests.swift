import Foundation
import Observation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KeypadPaymentObservationTests {
    private static let network = Network.mainnet
    private static let sol = Holding(id: .nativeSOL, amount: Amount(units: 1_500_000_000, decimals: 9), name: nil,
                                     symbol: "SOL", imageURL: nil, valuation: nil)
    private static let lessSOL = Holding(id: .nativeSOL, amount: Amount(units: 500_000_000, decimals: 9), name: nil,
                                         symbol: "SOL", imageURL: nil, valuation: nil)

    @Test func `The payment starts with the first balances and follows later ones`() async throws {
        try await withKeypad { account, observation, received in
            let balances = Observations { received.payment.model?.token.balance }

            observation.continuation.yield(update([Self.sol], of: account, revision: 1))

            for await balance in balances where balance == Decimal(string: "1.5") { break }
            let started = try #require(received.payment.model)

            observation.continuation.yield(update([Self.lessSOL], of: account, revision: 2))

            for await balance in balances where balance == Decimal(string: "0.5") { break }
            #expect(received.payment.model === started)
        }
    }

    @Test func `A portfolio without holdings that failed leaves nothing to send`() async throws {
        try await withKeypad { _, observation, received in
            let isLoading = Observations { received.payment.isLoading }

            observation.continuation.yield(Update(snapshot: nil, phase: .failed(ProviderClientError.invalidKey),
                                                  revision: 1))

            for await loading in isLoading where !loading { break }
            #expect(received.payment.model == nil)
        }
    }

    private func withKeypad(
        _ body: (widgets.Account, PortfolioResponses.Request, ReceivedKeypadPayment) async throws -> Void
    ) async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let account = try Account.fixture(index: 1)
        var requests = service.requests.makeAsyncIterator()
        let received = ReceivedKeypadPayment()
        let hosted = try HostedWindow(KeypadPaymentObservationRoot(portfolios: portfolios, account: account,
                                                                   network: Self.network, received: received))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        let viewing = Task { await portfolios.observe(account, on: Self.network) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        try await body(account, observation, received)
        viewing.cancel()
        await viewing.value
    }

    private func update(_ holdings: [Holding], of account: widgets.Account, revision: UInt64) -> Update {
        Update(snapshot: Snapshot(owner: account.address.value, network: Self.network, holdings: holdings),
               phase: .ready, revision: revision, snapshotRevision: revision)
    }
}
