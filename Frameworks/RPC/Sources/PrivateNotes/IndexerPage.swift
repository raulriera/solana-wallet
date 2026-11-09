import Encoding
import Foundation

/// One page of an indexer history stream that a pagination token continues.
protocol IndexerPage: Decodable, Sendable {
    /// The type of the page's rows.
    associatedtype Item: Sendable

    /// The page's rows in stream order.
    var items: [Item] { get }
    /// The ID of the newest tree that isn't paused, or `nil` when the indexer reports none.
    var outputTreeID: UInt16? { get }
    /// The token of the next page, or `nil` at the end of the stream.
    var paginationToken: String? { get }
    /// The highest slot that the indexer had stored when it answered.
    var contextSlot: UInt64 { get }
}

/// Where a read of an indexer history stream starts.
struct IndexerCheckpoint: Sendable, Hashable, Codable {
    /// The slot after which the read's rows start, or `nil` for the stream's first slot.
    let afterSlot: UInt64?
    /// The token of the page that continues an unfinished read, or `nil` for its first page.
    let paginationToken: String?

    /// The checkpoint at the stream's beginning.
    static let start = IndexerCheckpoint(afterSlot: nil, paginationToken: nil)
}

/// The rows of a stream's pages up to a page limit, whether the stream ended, and where a later read resumes.
struct IndexerRead<Item: Sendable>: Sendable {
    /// The rows of every page in stream order.
    let items: [Item]
    /// The ID of the newest tree that isn't paused, from the latest page that reports one.
    let outputTreeID: UInt16?
    /// The checkpoint after the last page's slot when the stream ended, else the checkpoint of the next page.
    let resume: IndexerCheckpoint
    /// Whether a page without a pagination token ended the stream.
    let isComplete: Bool
}

extension IndexerPage {
    /// Reads pages from a checkpoint until a page has no pagination token or the read reaches its page limit, halving
    /// the page size for the rest of the read whenever a page is too long.
    ///
    /// - Parameters:
    ///   - checkpoint: The checkpoint to start at.
    ///   - pageLimit: The most pages to fetch.
    ///   - pageSize: The most transactions to ask for in each page.
    ///   - page: The closure that fetches the page at a checkpoint with a page size.
    /// - Returns: The rows of the fetched pages, the reported output tree, the checkpoint to resume at, and whether
    ///   the stream ended.
    /// - Throws: ``RPCError/InvalidResponse/invalidCursor`` if the indexer repeats a pagination token or returns one
    ///   on a page without rows, ``RPCError/InvalidResponse/oversized`` for a one-transaction page that is too long,
    ///   or another error from `page`.
    static func read(
        from checkpoint: IndexerCheckpoint,
        pageLimit: Int,
        pageSize: Int,
        fetching page: (IndexerCheckpoint, Int) async throws -> Self
    ) async throws -> IndexerRead<Item> {
        var checkpoint = checkpoint
        var pageSize = pageSize
        var seen = Set([checkpoint.paginationToken].compactMap(\.self))
        var items: [Item] = []
        var outputTreeID: UInt16?
        var fetched = 0
        while fetched < pageLimit {
            try Task.checkCancellation()
            let current: Self
            do {
                current = try await page(checkpoint, pageSize)
            } catch RPCError.invalidResponse(.oversized) where pageSize > 1 {
                pageSize /= 2
                continue
            }
            fetched += 1
            items += current.items
            outputTreeID = current.outputTreeID ?? outputTreeID
            guard let next = current.paginationToken else {
                return IndexerRead(items: items, outputTreeID: outputTreeID,
                                   resume: IndexerCheckpoint(afterSlot: current.contextSlot, paginationToken: nil),
                                   isComplete: true)
            }
            guard !current.items.isEmpty, seen.insert(next).inserted else {
                throw RPCError.invalidResponse(.invalidCursor)
            }
            checkpoint = IndexerCheckpoint(afterSlot: checkpoint.afterSlot, paginationToken: next)
        }
        return IndexerRead(items: items, outputTreeID: outputTreeID, resume: checkpoint, isComplete: false)
    }
}

/// A page of shielded transactions, from a read by view tag or by nullifier.
struct ShieldedTransactionPage: IndexerPage {
    let items: [IndexedTransaction]
    let outputTreeID: UInt16?
    let paginationToken: String?
    let contextSlot: UInt64

    init(from decoder: any Decoder) throws {
        let page = try decoder.container(keyedBy: IndexerKey.self)
        items = try page.decodeRows(of: IndexedTransaction.self, forKey: .events)
        outputTreeID = try page.decodeIfPresent(UInt16.self, forKey: .outputTreeId)
        paginationToken = try page.decodePaginationToken()
        contextSlot = try page.decodeContextSlot()
    }
}

/// A page of encrypted outputs that match view tags.
struct EncryptedOutputPage: IndexerPage {
    let items: [EncryptedOutput]
    let outputTreeID: UInt16?
    let paginationToken: String?
    let contextSlot: UInt64

    init(from decoder: any Decoder) throws {
        let page = try decoder.container(keyedBy: IndexerKey.self)
        items = try page.decodeRows(of: EncryptedOutput.self, forKey: .outputs)
        outputTreeID = try page.decodeIfPresent(UInt16.self, forKey: .outputTreeId)
        paginationToken = try page.decodePaginationToken()
        contextSlot = try page.decodeContextSlot()
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

    /// The output as a proofless deposit, or `nil` when its transaction has a transaction viewing key or a salt or
    /// its payload isn't plaintext.
    var deposit: ShieldedTransaction? {
        guard transactionViewingKey == nil, salt == nil,
              output.payload.first == ShieldedOutput.Encoding.plaintext.rawValue else { return nil }
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
    case data, events, outputs, outputTreeId, paginationToken, context
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
}

extension KeyedDecodingContainer where K == IndexerKey {
    /// Decodes the rows of a page's transactions, in transaction order.
    ///
    /// - Parameters:
    ///   - type: The type of the rows.
    ///   - key: The key of each transaction's rows.
    /// - Returns: The rows of every transaction in `data`.
    /// - Throws: A decoding error for a missing or malformed `data` or row.
    fileprivate func decodeRows<Row: Decodable>(of type: Row.Type, forKey key: IndexerKey) throws -> [Row] {
        var transactions = try nestedUnkeyedContainer(forKey: .data)
        var rows: [Row] = []
        while !transactions.isAtEnd {
            rows += try transactions.nestedContainer(keyedBy: IndexerKey.self).decode([Row].self, forKey: key)
        }
        return rows
    }

    /// Decodes the token of the next page, treating `null` as the stream's end.
    ///
    /// - Returns: The token as received, or `nil` when the field is `null`.
    /// - Throws: A decoding error for a missing field or an empty token.
    fileprivate func decodePaginationToken() throws -> String? {
        guard let token = try decode(String?.self, forKey: .paginationToken) else { return nil }
        guard !token.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .paginationToken, in: self, debugDescription: "Empty token.")
        }
        return token
    }

    /// Decodes the highest slot that the indexer had stored when it answered.
    ///
    /// - Returns: The page's context slot.
    /// - Throws: A decoding error for a missing context or slot.
    fileprivate func decodeContextSlot() throws -> UInt64 {
        try nestedContainer(keyedBy: IndexerKey.self, forKey: .context).decode(UInt64.self, forKey: .slot)
    }
}
