import Foundation
import Testing
@testable import widgets

/// Verifies that each private-balance error has an alert title and explanation that name no provider.
struct PrivateBalanceErrorTests {
    /// Every error explains itself in an alert without naming a provider.
    /// - Parameter error: A private-balance error.
    @Test(arguments: PrivateBalanceError.allCases)
    func `Errors explain themselves without naming a provider`(error: PrivateBalanceError) throws {
        let title = try #require(error.errorDescription)
        let message = try #require(error.recoverySuggestion)

        #expect(!title.isEmpty)
        #expect(!message.isEmpty)
        for provider in ["Helius", "QuickNode", "Jupiter", "Solana RPC"] {
            #expect(![title, message].contains { $0.localizedStandardContains(provider) })
        }
    }

    /// Each error explains a different problem.
    @Test
    func `Each error has its own explanation`() {
        let messages = PrivateBalanceError.allCases.compactMap(\.recoverySuggestion)

        #expect(Set(messages).count == PrivateBalanceError.allCases.count)
    }
}
