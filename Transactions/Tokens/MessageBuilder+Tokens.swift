public import Foundation

extension MessageBuilder: TokenMessageBuilding {
    /// Constructs a token transfer for either program using their shared wire layout.
    ///
    /// Destination creation is idempotent, so another sender creating the account
    /// before execution doesn't invalidate the instruction. Token-2022 fees are
    /// checked on-chain; a changed fee requires a new preparation and approval.
    ///
    /// - Parameters:
    ///   - transfer: The validated token accounts, amount, fee, and optional memo.
    ///   - recentBlockhash: The exact blockhash to encode without refreshing it.
    ///   - configuration: The explicit fee and resource limits.
    /// - Returns: An unsigned V1 message with one required signer.
    /// - Throws: ``ValidationError`` for an invalid blockhash or oversized message.
    public func message(for transfer: TokenTransfer, recentBlockhash: String,
                        configuration: Configuration) throws -> Data {
        let program = try Address(transfer.mint.program.rawValue)
        var instructions: [MessageEncoder.Instruction] = []
        if transfer.createsDestination {
            instructions.append(.init(
                program: try Address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                accounts: [(transfer.sender, true), (transfer.destination, true), (transfer.recipient, false),
                           (transfer.mint.address, false), (try Address("11111111111111111111111111111111"), false),
                           (program, false)], data: Data([1]) // CreateIdempotent.
            ))
        }
        if let memo = transfer.memo {
            instructions.append(.init(program: try Address("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
                                      accounts: [(transfer.sender, false)], data: Data(memo.utf8)))
        }
        var payload = Data(transfer.expectedFee == nil ? [12] : [26, 1])
        payload.appendLittleEndian(transfer.amount)
        payload.append(transfer.mint.decimals)
        if let fee = transfer.expectedFee { payload.appendLittleEndian(fee) }
        instructions.append(.init(program: program,
                                  accounts: [(transfer.source.address, true), (transfer.mint.address, false),
                                             (transfer.destination, true), (transfer.sender, false)], data: payload))
        return try MessageEncoder.encode(payer: transfer.sender, instructions: instructions,
                                         recentBlockhash: recentBlockhash, configuration: configuration)
    }
}
