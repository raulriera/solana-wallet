import CryptoKit
import Foundation

/// A validated English BIP-39 recovery phrase.
public struct RecoveryPhrase: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A supported BIP-39 phrase length.
    public enum WordCount: Int, CaseIterable, Sendable {
        case twelve = 12
        case fifteen = 15
        case eighteen = 18
        case twentyOne = 21
        case twentyFour = 24

        var entropyByteCount: Int { rawValue / 3 * 4 }
    }

    /// An error from validating a recovery phrase.
    public enum ValidationError: Error, Equatable {
        case invalidWordCount
        /// The word at a zero-based position isn't in the English word list.
        case unknownWord(position: Int)
        case invalidChecksum
        /// The entropy doesn't have a supported byte count.
        case invalidEntropy
    }

    public let words: [String]

    public var description: String { "RecoveryPhrase" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates a recovery phrase by validating and normalizing its words.
    ///
    /// - Parameter phrase: The recovery words separated by whitespace.
    /// - Throws: ``ValidationError`` if the length, words, or checksum are invalid.
    public init(_ phrase: String) throws {
        let words = phrase.decomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard let count = WordCount(rawValue: words.count) else {
            throw ValidationError.invalidWordCount
        }
        let indices = try words.enumerated().map { position, word in
            guard let index = English.indices[word] else {
                throw ValidationError.unknownWord(position: position)
            }
            return index
        }
        let bits = indices.flatMap { index in
            (0..<11).reversed().map { (index >> $0) & 1 }
        }
        var entropy = [UInt8](repeating: 0, count: count.entropyByteCount)
        for bit in 0..<(entropy.count * 8) {
            entropy[bit / 8] |= UInt8(bits[bit] << (7 - bit % 8))
        }
        let expected = try Self(entropy: entropy)
        guard words == expected.words else { throw ValidationError.invalidChecksum }
        self.words = words
    }

    /// Creates a recovery phrase that encodes entropy.
    ///
    /// - Parameter entropy: 16 to 32 bytes, in steps of four.
    /// - Throws: ``ValidationError/invalidEntropy`` if the byte count is unsupported.
    init(entropy: [UInt8]) throws {
        guard let count = WordCount.allCases.first(where: { $0.entropyByteCount == entropy.count }) else {
            throw ValidationError.invalidEntropy
        }
        let checksum = Array(SHA256.hash(data: entropy))[0]
        let bytes = entropy + [checksum]
        words = (0..<count.rawValue).map { word in
            var index = 0
            for bit in (word * 11)..<(word * 11 + 11) {
                index = (index << 1) | Int((bytes[bit / 8] >> (7 - bit % 8)) & 1)
            }
            return English.words[index]
        }
    }
}
