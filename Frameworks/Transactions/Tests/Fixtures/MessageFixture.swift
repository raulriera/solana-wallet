import Transactions

/// Public Solana example inputs with message bytes produced by Kit 8.0.0.
///
/// See `references/transactions.md` for the source and generation procedure.
struct MessageFixture: Sendable {
    static let sender = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
    static let recipient = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    static let zeroBlockhash = "11111111111111111111111111111111"

    let name: String
    let lamports: UInt64
    let priorityFeeLamports: UInt64
    let computeUnitLimit: UInt32
    let loadedAccountsDataSizeLimit: UInt32
    let heapSize: UInt32?
    let blockhash: String
    let message: String

    /// Creates the resource configuration represented by the fixture.
    ///
    /// - Returns: A configuration with the fixture's explicit fee and limits.
    /// - Throws: A validation error if the fixture is invalid.
    func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: priorityFeeLamports, computeUnitLimit: computeUnitLimit,
                          loadedAccountsDataSizeLimit: loadedAccountsDataSizeLimit, heapSize: heapSize)
    }

    static let transfers = [
        MessageFixture(
            name: "official example", lamports: 1, priorityFeeLamports: 5000,
            computeUnitLimit: 20000, loadedAccountsDataSizeLimit: 65536, heapSize: 65_536,
            blockhash: zeroBlockhash,
            message: "gQEAAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEDMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiBMAAAAAAAAgTgAAAAABAAAAAQACAgwAAAECAAAAAQAAAAAAAAA="
        ),
        MessageFixture(
            name: "zero fee minimum limits minimum heap", lamports: 1, priorityFeeLamports: 0,
            computeUnitLimit: 1, loadedAccountsDataSizeLimit: 1, heapSize: 32_768,
            blockhash: zeroBlockhash,
            message: "gQEAAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEDMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAQAAAACAAAACAgwAAAECAAAAAQAAAAAAAAA="
        ),
        MessageFixture(
            name: "maximum heap nonzero blockhash", lamports: 1, priorityFeeLamports: 0,
            computeUnitLimit: 20000, loadedAccountsDataSizeLimit: 65536, heapSize: 262_144,
            blockhash: recipient,
            message: "gQEAAR8AAAB+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gEDMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgTgAAAAABAAAABAACAgwAAAECAAAAAQAAAAAAAAA="
        )
    ]

    static let selfTransfer = MessageFixture(
            name: "self transfer maximum integers default heap", lamports: UInt64.max, priorityFeeLamports: UInt64.max,
            computeUnitLimit: 1400000, loadedAccountsDataSizeLimit: 67108864, heapSize: nil,
            blockhash: zeroBlockhash,
            message: "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAECMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//////////wFwVAAAAAAQBAgwAAAACAAAA//////////8="
        )
}
