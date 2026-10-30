import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountsSceneTests {
    @Test
    func `Opening Accounts reads no recovery`() async throws {
        let wallet = try await PublicWalletAccounts()
        let hosted = try wallet.hosted(AccountsScene(account: .constant(wallet.first)))
        defer { hosted.close() }

        try #require(try await hosted.appears())

        #expect(await wallet.recovery.reads.isEmpty)
        #expect(await wallet.storage.value == [wallet.first])
    }
}
