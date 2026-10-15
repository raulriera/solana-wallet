import Encoding
public import Foundation

/// A stateless V1 compiler shared by every program's instructions.
public struct MessageBuilder: MessageBuilding {
    /// Creates a compiler without network, storage, or signing dependencies.
    public init() {}

    /// Merges account permissions while preserving instruction and argument order,
    /// and writes all instruction headers before their payloads.
    ///
    /// - Parameters:
    ///   - instructions: The invocations composing one atomic transaction.
    ///   - payer: The writable fee payer, placed before all other required signers.
    ///   - recentBlockhash: The exact blockhash; freshness requires an RPC check.
    ///   - configuration: The V1 fee and resource requests.
    /// - Returns: The bytes covered by every required signature.
    /// - Throws: A validation error for an invalid blockhash, conflicting roles, or a composition
    ///   that cannot fit one V1 transaction.
    public func message(instructions: [Instruction], payer: Address, recentBlockhash: String,
                        configuration: Configuration) throws -> Data {
        guard let blockhash = Base58.decode(recentBlockhash, byteCount: 32) else {
            throw ValidationError.invalidBlockhash
        }
        guard !instructions.isEmpty, instructions.count <= 64,
              instructions.allSatisfy({ $0.accounts.count <= 255 && $0.data.count <= 4_032 }) else {
            throw ValidationError.invalidMessage
        }
        var order = [payer]
        var writable: Set<Address> = [payer]
        var signers: Set<Address> = [payer]
        let programs = Set(instructions.map(\.program))
        for instruction in instructions {
            for account in instruction.accounts {
                if !order.contains(account.address) { order.append(account.address) }
                if account.isWritable { writable.insert(account.address) }
                if account.isSigner { signers.insert(account.address) }
            }
            if !order.contains(instruction.program) { order.append(instruction.program) }
        }
        guard programs.isDisjoint(with: writable), signers.count <= 12, order.count <= 64 else { throw ValidationError.invalidMessage }
        let writableSigners = order.filter { signers.contains($0) && writable.contains($0) }
        let readonlySigners = order.filter { signers.contains($0) && !writable.contains($0) }
        let writableOthers = order.filter { !signers.contains($0) && writable.contains($0) }
        let readonlyOthers = order.filter { !signers.contains($0) && !writable.contains($0) }
        let accounts = writableSigners + readonlySigners + writableOthers + readonlyOthers
        let indices = Dictionary(uniqueKeysWithValues: accounts.enumerated().map { ($0.element, UInt8($0.offset)) })
        var message = Data([0x81, UInt8(signers.count), UInt8(readonlySigners.count), UInt8(readonlyOthers.count)])
        message.appendLittleEndian(UInt32(configuration.heapSize == nil ? 0x0f : 0x1f))
        message.append(contentsOf: blockhash)
        message.append(contentsOf: [UInt8(instructions.count), UInt8(accounts.count)])
        for account in accounts { message.append(contentsOf: account.bytes) }
        message.appendLittleEndian(configuration.priorityFeeLamports)
        message.appendLittleEndian(configuration.computeUnitLimit)
        message.appendLittleEndian(configuration.loadedAccountsDataSizeLimit)
        if let heap = configuration.heapSize { message.appendLittleEndian(heap) }
        for instruction in instructions {
            guard let program = indices[instruction.program] else { throw ValidationError.invalidMessage }
            message.append(contentsOf: [program, UInt8(instruction.accounts.count)])
            message.appendLittleEndian(UInt16(instruction.data.count))
        }
        for instruction in instructions {
            for account in instruction.accounts {
                guard let index = indices[account.address] else { throw ValidationError.invalidMessage }
                message.append(index)
            }
            message.append(instruction.data)
        }
        guard message.count + signers.count * 64 <= 4_096 else { throw ValidationError.invalidMessage }
        return message
    }
}
