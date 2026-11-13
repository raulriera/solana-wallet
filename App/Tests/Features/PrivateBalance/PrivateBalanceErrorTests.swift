import Foundation
import Testing
@testable import widgets

struct PrivateBalanceErrorTests {
    @Test(arguments: PrivateBalanceError.allCases)
    func `Errors explain themselves without naming a provider`(error: PrivateBalanceError) throws {
        let title = try #require(error.errorDescription)
        let message = try #require(error.recoverySuggestion)

        #expect(!title.isEmpty)
        #expect(!message.isEmpty)
        for provider in ["Helius", "Jupiter", "Solana RPC"] {
            #expect(![title, message].contains { $0.localizedStandardContains(provider) })
        }
    }

    @Test
    func `Each error has its own explanation`() {
        let messages = PrivateBalanceError.allCases.compactMap(\.recoverySuggestion)

        #expect(Set(messages).count == PrivateBalanceError.allCases.count)
    }
}
