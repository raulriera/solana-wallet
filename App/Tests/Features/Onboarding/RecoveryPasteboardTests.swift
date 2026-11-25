import Foundation
import Testing
import UIKit
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RecoveryPasteboardTests {
    @Test
    func `Copied words keep their order separated by single spaces`() throws {
        let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name(UUID().uuidString), create: true))
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        RecoveryPasteboard(pasteboard: pasteboard).copy(try RecoveryPhrase(ThrowawayWallet.words))

        #expect(pasteboard.string == ThrowawayWallet.words)
    }

    @Test
    func `Copied words leave the pasteboard when they expire`() async throws {
        let pasteboard = try #require(UIPasteboard(name: UIPasteboard.Name(UUID().uuidString), create: true))
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let copying = RecoveryPasteboard(pasteboard: pasteboard, lifetime: .milliseconds(500))

        copying.copy(try RecoveryPhrase(ThrowawayWallet.words))
        try #require(pasteboard.hasStrings)
        try await Task.sleep(for: .seconds(1))

        #expect(!pasteboard.hasStrings)
    }
}
