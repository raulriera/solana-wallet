import Encoding
import Foundation

extension TokenProgram {
    /// Creates a checked token transfer instruction.
    ///
    /// - Parameters:
    ///   - amount: The debit in base units.
    ///   - decimals: The mint's decimals.
    ///   - source: The token account that sends.
    ///   - mint: The mint of both token accounts.
    ///   - destination: The token account that receives.
    ///   - authority: The source account's owner, who signs.
    ///   - fee: The Token-2022 transfer fee the instruction asserts, or `nil` for a mint without transfer fees.
    /// - Returns: The checked transfer instruction.
    /// - Throws: ``ValidationError/invalidAddress`` if the program's address is invalid.
    public func transferChecked(_ amount: UInt64, decimals: UInt8, from source: Address, mint: Address,
                                to destination: Address, authority: Address, fee: UInt64? = nil) throws -> Instruction {
        var data = Data(fee == nil ? [12] : [26, 1])
        data.append(littleEndian: amount)
        data.append(decimals)
        if let fee { data.append(littleEndian: fee) }
        return Instruction(program: try address, accounts: [
            .writable(source),
            .readonly(mint),
            .writable(destination),
            .readonly(authority, isSigner: true),
        ], data: data)
    }
}
