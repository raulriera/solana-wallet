import Observation
import Portfolio
import SwiftUI
import Testing
@testable import widgets

/// Runs turning private balances on from SOL's details in a real window.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceLifecycleTests {
    /// A request to turn private balances on runs in the details' task, which then shows the balance.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `Turning on runs in the details' task`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        await model.refresh(for: account)
        let details = TokenDetailScreen(holding: Holding(id: .nativeSOL, amount: Amount(units: 0, decimals: 9),
                                                         name: "Solana", symbol: "SOL", imageURL: nil, valuation: nil),
                                        privateBalance: model)
        let hosted = try HostedWindow(NavigationStack { details.privateBalanceLifecycle() })
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        model.turnOn()

        // The suite's time limit ends the wait if the attempt never finishes.
        for await isTurnedOn in Observations({ model.isTurnedOn }) where isTurnedOn { break }
        #expect(model.status == .unregistered)
        #expect(!model.isTurningOn)
    }
}
