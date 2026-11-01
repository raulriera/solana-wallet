import Encoding
import Foundation

/// One page of an indexer stream that a cursor orders.
protocol IndexerPage: Decodable, Sendable {
    /// The type of the page's rows.
    associatedtype Item: Sendable

    /// The page's rows in stream order.
    var items: [Item] { get }
    /// The ID of the newest tree that isn't paused, or `nil` when the indexer reports none.
    var outputTreeID: UInt16? { get }
    /// The cursor after the page's last row, or `nil` at the end of the stream.
    var nextCursor: String? { get }
    /// The position that the scan reached, on a page that the limit didn't fill.
    var scannedThrough: String? { get }
}

/// The rows of a stream read to its end, and where a later read resumes.
struct IndexerRead<Item: Sendable>: Sendable {
    /// The rows of every page in stream order.
    let items: [Item]
    /// The ID of the newest tree that isn't paused, from the latest page that reports one.
    let outputTreeID: UInt16?
    /// The last scanned position or next cursor that a page reported, else the starting cursor.
    let resumeCursor: String?
}

extension IndexerPage {
    /// Reads pages from a cursor until a page has no next cursor.
    ///
    /// - Parameters:
    ///   - cursor: The cursor to start after, or `nil` to start at the beginning.
    ///   - page: The closure that fetches the page after a cursor.
    /// - Returns: Every row, the reported output tree, and the resume cursor.
    /// - Throws: ``RPCError/InvalidResponse/invalidCursor`` if the indexer repeats a cursor or returns one on a page
    ///   without rows, or an error from `page`.
    static func readAll(from cursor: String?, fetching page: (String?) async throws -> Self) async throws
        -> IndexerRead<Item> {
        var cursor = cursor
        var resumeCursor = cursor
        var seen = Set([cursor].compactMap(\.self))
        var items: [Item] = []
        var outputTreeID: UInt16?
        while true {
            try Task.checkCancellation()
            let current = try await page(cursor)
            items += current.items
            outputTreeID = current.outputTreeID ?? outputTreeID
            resumeCursor = current.scannedThrough ?? current.nextCursor ?? resumeCursor
            guard let next = current.nextCursor else {
                return IndexerRead(items: items, outputTreeID: outputTreeID, resumeCursor: resumeCursor)
            }
            guard !current.items.isEmpty, seen.insert(next).inserted else {
                throw RPCError.invalidResponse(.invalidCursor)
            }
            cursor = next
        }
    }
}

/// A page of shielded transactions, from a read by view tag or by nullifier.
struct ShieldedTransactionPage: IndexerPage {
    let items: [IndexedTransaction]
    let outputTreeID: UInt16?
    let nextCursor: String?
    let scannedThrough: String?

    init(from decoder: any Decoder) throws {
        let page = try decoder.container(keyedBy: IndexerKey.self)
        items = try page.decode([IndexedTransaction].self, forKey: .transactions)
        outputTreeID = try page.decodeIfPresent(UInt16.self, forKey: .outputTreeId)
        nextCursor = try page.decodeCursor(forKey: .nextCursor)
        scannedThrough = try page.decodeCursor(forKey: .scannedThrough)
    }
}

/// A page of encrypted outputs that match view tags.
struct EncryptedOutputPage: IndexerPage {
    let items: [EncryptedOutput]
    let outputTreeID: UInt16?
    let nextCursor: String?
    let scannedThrough: String?

    init(from decoder: any Decoder) throws {
        let page = try decoder.container(keyedBy: IndexerKey.self)
        items = try page.decode([EncryptedOutput].self, forKey: .matches)
        outputTreeID = try page.decodeIfPresent(UInt16.self, forKey: .outputTreeId)
        nextCursor = try page.decodeCursor(forKey: .nextCursor)
        scannedThrough = try page.decodeCursor(forKey: .scannedThrough)
    }
}

/// One output that matched a view tag, with its transaction's encryption fields.
struct EncryptedOutput: Decodable, Sendable, Equatable {
    let slot: UInt64
    /// The transaction's base-58 signature.
    let signature: String
    let output: ShieldedOutput
    /// The transaction viewing public key, or `nil` without encrypted notes.
    let transactionViewingKey: [UInt8]?
    /// The note salt, or `nil` without encrypted notes.
    let salt: [UInt8]?

    private static let plaintextEncoding: UInt8 = 0

    /// The output as a proofless deposit, or `nil` when its transaction has a transaction viewing key or a salt or
    /// its payload isn't plaintext.
    var deposit: ShieldedTransaction? {
        guard transactionViewingKey == nil, salt == nil, output.payload.first == Self.plaintextEncoding else {
            return nil
        }
        return ShieldedTransaction(signature: signature, slot: slot, eventIndex: nil, transactionViewingKey: nil,
                                   salt: nil, outputs: [output], nullifiers: [], isProofless: true)
    }

    init(from decoder: any Decoder) throws {
        let match = try decoder.container(keyedBy: IndexerKey.self)
        slot = try match.decode(UInt64.self, forKey: .slot)
        signature = try match.decodeSignature(forKey: .txSignature)
        output = try match.decode(IndexedOutput.self, forKey: .outputSlot).value
        transactionViewingKey = try match.decodeBase64IfPresent(forKey: .txViewingPk, count: 33)
        salt = try match.decodeBase64IfPresent(forKey: .salt, count: 16)
    }
}

/// A strictly decoded indexed shielded transaction, and whether a ring authorized it.
struct IndexedTransaction: Decodable, Sendable, Equatable {
    let value: ShieldedTransaction
    /// Whether the transaction names a ring's config account or program.
    let isInRing: Bool

    init(from decoder: any Decoder) throws {
        let transaction = try decoder.container(keyedBy: IndexerKey.self)
        value = ShieldedTransaction(
            signature: try transaction.decodeSignature(forKey: .txSignature),
            slot: try transaction.decode(UInt64.self, forKey: .slot),
            eventIndex: try transaction.decodeIfPresent(UInt16.self, forKey: .eventIndex),
            transactionViewingKey: try transaction.decodeBase64IfPresent(forKey: .txViewingPk, count: 33),
            salt: try transaction.decodeBase64IfPresent(forKey: .salt, count: 16),
            outputs: try transaction.decode([IndexedOutput].self, forKey: .outputSlots).map(\.value),
            nullifiers: try transaction.decode([IndexedHash].self, forKey: .nullifiers).map(\.bytes),
            isProofless: try transaction.decode(Bool.self, forKey: .proofless)
        )
        let ringConfig = try transaction.decodeAddressIfPresent(forKey: .ringConfig)
        let ringProgramID = try transaction.decodeAddressIfPresent(forKey: .ringProgramId)
        isInRing = ringConfig != nil || ringProgramID != nil
    }
}

/// A strictly decoded output slot and its context.
private struct IndexedOutput: Decodable {
    let value: ShieldedOutput

    init(from decoder: any Decoder) throws {
        let slot = try decoder.container(keyedBy: IndexerKey.self)
        let context = try slot.nestedContainer(keyedBy: IndexerKey.self, forKey: .outputContext)
        value = ShieldedOutput(
            viewTag: try slot.decode(IndexedHash.self, forKey: .viewTag).bytes,
            utxoHash: try context.decode(IndexedHash.self, forKey: .hash).bytes,
            treeID: try context.decode(UInt16.self, forKey: .treeId),
            leafIndex: try context.decode(UInt64.self, forKey: .leafIndex),
            payload: try slot.decodeBase64(forKey: .payload)
        )
    }
}

/// A 32-byte hash that an indexer encodes in base 58.
struct IndexedHash: Decodable, Sendable {
    let bytes: [UInt8]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let bytes = Base58.decode(try container.decode(String.self), byteCount: 32) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid 32-byte hash.")
        }
        self.bytes = bytes
    }
}

/// The field names of indexer pages and their rows.
private enum IndexerKey: String, CodingKey {
    case transactions, matches, outputTreeId, nextCursor, scannedThrough
    case slot, txSignature, eventIndex, txViewingPk, salt, outputSlots, outputSlot, nullifiers, proofless
    case viewTag, outputContext, payload, hash, treeId, leafIndex, ringConfig, ringProgramId
}

extension KeyedDecodingContainer {
    /// Decodes a base-58 transaction signature of 64 bytes, keeping its text.
    ///
    /// - Parameter key: The field's key.
    /// - Returns: The signature as received.
    /// - Throws: A decoding error for a missing field or a value that isn't a 64-byte signature.
    fileprivate func decodeSignature(forKey key: Key) throws -> String {
        let signature = try decode(String.self, forKey: key)
        guard Base58.decode(signature, byteCount: 64) != nil else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid signature.")
        }
        return signature
    }

    /// Decodes an optional base-58 address of 32 bytes, treating `null` as absent.
    ///
    /// - Parameter key: The field's key.
    /// - Returns: The address as received, or `nil` when the field is absent or `null`.
    /// - Throws: A decoding error for a value that isn't a 32-byte address.
    fileprivate func decodeAddressIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let address = try decode(String.self, forKey: key)
        guard Base58.decode(address, byteCount: 32) != nil else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid address.")
        }
        return address
    }

    /// Decodes canonical standard base 64 with padding.
    ///
    /// - Parameter key: The field's key.
    /// - Returns: The decoded bytes.
    /// - Throws: A decoding error for a missing field or a non-canonical encoding.
    fileprivate func decodeBase64(forKey key: Key) throws -> [UInt8] {
        let text = try decode(String.self, forKey: key)
        guard let data = Data(base64Encoded: text), data.base64EncodedString() == text else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid base 64.")
        }
        return Array(data)
    }

    /// Decodes optional canonical base 64 of a fixed length, treating `null` as absent.
    ///
    /// - Parameters:
    ///   - key: The field's key.
    ///   - count: The required number of decoded bytes.
    /// - Returns: The decoded bytes, or `nil` when the field is absent or `null`.
    /// - Throws: A decoding error for a non-canonical encoding or another length.
    fileprivate func decodeBase64IfPresent(forKey key: Key, count: Int) throws -> [UInt8]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let bytes = try decodeBase64(forKey: key)
        guard bytes.count == count else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid length.")
        }
        return bytes
    }

    /// Decodes an optional canonical base-64 cursor, treating `null` as absent.
    ///
    /// - Parameter key: The field's key.
    /// - Returns: The cursor as received, or `nil` when the field is absent or `null`.
    /// - Throws: A decoding error for a non-canonical encoding.
    fileprivate func decodeCursor(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        _ = try decodeBase64(forKey: key)
        return try decode(String.self, forKey: key)
    }
}
