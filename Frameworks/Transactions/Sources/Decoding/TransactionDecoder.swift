import Encoding
public import Foundation

/// A stateless inspector for complete V1 envelopes with one or more required signers.
public struct TransactionDecoder: TransactionDecoding {
    /// Creates a decoder without networking, key access, or shared mutable state.
    public init() {}

    /// Imports bounded Base64 without asking workflow callers to construct byte buffers.
    ///
    /// - Parameter base64: A complete V1 transaction, without whitespace or ignored characters.
    /// - Returns: The decoded transaction with its exact message bytes preserved.
    /// - Throws: ``ValidationError`` for invalid encoding, size, or structure.
    public func decode(base64: String) throws -> Transaction {
        // A 4,096-byte envelope needs at most 5,464 Base64 characters.
        guard base64.utf8.prefix(5_465).count <= 5_464,
              let data = Data(base64Encoded: base64) else { throw ValidationError.invalidTransaction }
        return try decode(data)
    }

    /// Checks V1 framing and account references while retaining exact message bytes.
    ///
    /// The decoder accepts zero-filled signature slots for unsigned or partially
    /// signed transactions. It doesn't verify signatures, interpret program data,
    /// determine blockhash freshness, or guarantee runtime acceptance.
    ///
    /// - Parameter data: A complete V1 transaction of at most 4,096 bytes.
    /// - Returns: Immutable inspection data with ordered accounts and signature slots.
    /// - Throws: ``ValidationError`` for unsupported versions/configuration, malformed
    ///   structure, duplicate addresses, invalid indices, or an invalid heap request.
    public func decode(_ data: Data) throws -> Transaction {
        guard !data.isEmpty, data.count <= 4_096 else { throw ValidationError.invalidTransaction }
        var reader = ByteReader(data)
        let version: UInt8 = try reader.integer()
        guard version == 0x81 else { throw ValidationError.unsupportedVersion }
        let signerCount = Int(try reader.integer() as UInt8)
        let readonlySigners = Int(try reader.integer() as UInt8)
        let readonlyOthers = Int(try reader.integer() as UInt8)
        let mask: UInt32 = try reader.integer()
        guard mask & ~UInt32(0x1f) == 0 else { throw ValidationError.unsupportedConfiguration }
        guard mask & 3 == 0 || mask & 3 == 3 else { throw ValidationError.invalidTransaction }
        let lifetime = Base58.encode(Array(try reader.read(count: 32)))
        let instructionCount = Int(try reader.integer() as UInt8)
        let accountCount = Int(try reader.integer() as UInt8)
        guard (1...12).contains(signerCount), readonlySigners < signerCount,
              accountCount <= 64, signerCount + readonlyOthers <= accountCount,
              instructionCount <= 64 else { throw ValidationError.invalidTransaction }

        var accounts: [Transaction.Account] = []
        var addresses: Set<Address> = []
        for index in 0..<accountCount {
            let address = try Address(Base58.encode(Array(reader.read(count: 32))))
            guard addresses.insert(address).inserted else { throw ValidationError.invalidTransaction }
            let isSigner = index < signerCount
            let isWritable = isSigner ? index < signerCount - readonlySigners : index < accountCount - readonlyOthers
            accounts.append(.init(address: address, isSigner: isSigner, isWritable: isWritable))
        }
        let requests = try requests(mask: mask, reader: &reader)
        var headers: [(program: Int, accounts: Int, bytes: Int)] = []
        for _ in 0..<instructionCount {
            let program = Int(try reader.integer() as UInt8)
            let count = Int(try reader.integer() as UInt8)
            let bytes = Int(try reader.integer() as UInt16)
            guard program > 0, program < accountCount else { throw ValidationError.invalidTransaction }
            headers.append((program, count, bytes))
        }
        var instructions: [Transaction.Instruction] = []
        for header in headers {
            let indices = try reader.read(count: header.accounts).map(Int.init)
            guard indices.allSatisfy({ $0 < accountCount }) else { throw ValidationError.invalidTransaction }
            instructions.append(.init(programIndex: header.program, accountIndices: indices,
                                      data: try reader.read(count: header.bytes)))
        }
        let message = Data(data.prefix(reader.offset))
        var signatures: [Data] = []
        for _ in 0..<signerCount { signatures.append(try reader.read(count: 64)) }
        guard reader.offset == data.count else { throw ValidationError.invalidTransaction }
        return Transaction(message: message, lifetimeSpecifier: lifetime, accounts: accounts,
                           requests: requests, instructions: instructions, signatures: signatures)
    }

    /// Reads supported configuration fields in mask order without supplying defaults.
    ///
    /// - Parameters:
    ///   - mask: The validated configuration mask.
    ///   - reader: The reader positioned at the first configuration value.
    /// - Returns: The encoded requests, retaining `nil` for omitted fields.
    /// - Throws: A truncation error or ``ValidationError/invalidHeapSize``.
    private func requests(mask: UInt32, reader: inout ByteReader) throws -> Transaction.Requests {
        let fee: UInt64? = mask & 3 == 3 ? try reader.integer() : nil
        let compute: UInt32? = mask & 4 != 0 ? try reader.integer() : nil
        let accountData: UInt32? = mask & 8 != 0 ? try reader.integer() : nil
        let heap: UInt32? = mask & 16 != 0 ? try reader.integer() : nil
        try Configuration.validateHeapSize(heap)
        return .init(priorityFeeLamports: fee, computeUnitLimit: compute,
                     loadedAccountsDataSizeLimit: accountData, heapSize: heap)
    }
}
