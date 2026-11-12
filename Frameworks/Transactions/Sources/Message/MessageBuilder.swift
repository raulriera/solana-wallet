import Encoding
public import Foundation

/// A message builder that compiles instructions into V1 messages.
public struct MessageBuilder: MessageBuilding {
    /// Creates a message builder.
    public init() {}

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
        message.append(littleEndian: UInt32(configuration.heapSize == nil ? 0x0f : 0x1f))
        message.append(contentsOf: blockhash)
        message.append(contentsOf: [UInt8(instructions.count), UInt8(accounts.count)])
        for account in accounts { message.append(contentsOf: account.bytes) }
        message.append(littleEndian: configuration.priorityFeeLamports)
        message.append(littleEndian: configuration.computeUnitLimit)
        message.append(littleEndian: configuration.loadedAccountsDataSizeLimit)
        if let heap = configuration.heapSize { message.append(littleEndian: heap) }
        for instruction in instructions {
            guard let program = indices[instruction.program] else { throw ValidationError.invalidMessage }
            message.append(contentsOf: [program, UInt8(instruction.accounts.count)])
            message.append(littleEndian: UInt16(instruction.data.count))
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
