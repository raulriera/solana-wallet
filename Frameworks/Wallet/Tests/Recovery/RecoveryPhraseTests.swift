import Foundation
import Testing
@testable import Wallet

struct RecoveryPhraseTests {
    @Test(arguments: try BIP39Vector.examples())
    func `Known entropy produces the BIP-39 recovery words`(vector: BIP39Vector) throws {
        let entropy = try fixtureBytes(vector.entropy)
        let count = try #require(RecoveryPhrase.WordCount(rawValue: vector.phrase.split(separator: " ").count))
        let wallet = Wallet(entropy: FixedEntropy(value: entropy))

        let generated = try wallet.recoveryPhrase(wordCount: count)
        let imported = try RecoveryPhrase(vector.phrase)

        #expect(generated.words.joined(separator: " ") == vector.phrase)
        #expect(imported.words == generated.words)
    }

    @Test(arguments: [0, 1, 11, 13, 25])
    func `Recovery phrases reject unsupported word counts`(count: Int) {
        let phrase = Array(repeating: "abandon", count: count).joined(separator: " ")
        #expect(throws: RecoveryPhrase.ValidationError.invalidWordCount) {
            try RecoveryPhrase(phrase)
        }
    }

    @Test
    func `Unknown recovery words report their position`() {
        let phrase = Array(repeating: "abandon", count: 11).joined(separator: " ") + " not-a-bip39-word"
        #expect(throws: RecoveryPhrase.ValidationError.unknownWord(position: 11)) {
            try RecoveryPhrase(phrase)
        }
    }

    @Test
    func `Recovery phrases reject an incorrect checksum`() {
        #expect(throws: RecoveryPhrase.ValidationError.invalidChecksum) {
            try RecoveryPhrase(Array(repeating: "abandon", count: 12).joined(separator: " "))
        }
    }

    @Test
    func `Unavailable secure randomness prevents phrase creation`() {
        let wallet = Wallet(entropy: UnavailableEntropy())
        #expect(throws: UnavailableEntropyError.unavailable) {
            try wallet.recoveryPhrase(wordCount: .twelve)
        }
    }
}

private struct FixedEntropy: EntropyProviding {
    let value: [UInt8]

    func bytes(count: Int) -> [UInt8] {
        #expect(count == value.count)
        return value
    }
}

private enum UnavailableEntropyError: Error { case unavailable }

private struct UnavailableEntropy: EntropyProviding {
    func bytes(count: Int) throws -> [UInt8] {
        throw UnavailableEntropyError.unavailable
    }
}
