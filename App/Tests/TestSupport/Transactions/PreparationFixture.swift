import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

enum PreparationFixture {
    static func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                          loadedAccountsDataSizeLimit: 65_536, heapSize: 65_536)
    }

    static func preparation(fee: UInt64? = 10_000, error: TransactionError? = nil) throws -> Preparation {
        let transfer = try SystemProgram.transfer(from: Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), to: Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"), lamports: 1
        )
        let message = try #require(Data(base64Encoded:
            "gQEAAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEDMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiBMAAAAAAAAgTgAAAAABAAAAAQACAgwAAAECAAAAAQAAAAAAAAA="
        ))
        return Preparation(
            source: .local([transfer], transfer.accounts[0].address, try configuration(), .init(context: Context(slot: 400), value: .init(
                blockhash: "11111111111111111111111111111111", lastValidBlockHeight: 550
            ))), signer: transfer.accounts[0].address,
            transaction: try TransactionDecoder().decode(message + Data(repeating: 0, count: 64)), network: .devnet,
            fee: .init(context: Context(slot: 401), value: fee),
            simulation: .init(context: Context(slot: 402), value: .init(
                error: error, logs: error == nil ? ["Program completed"] : ["Transfer: insufficient lamports 0, need 1"],
                unitsConsumed: 150, loadedAccountsDataSize: 256, fee: fee, replacementBlockhash: nil,
                preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
            ))
        )
    }

    static func source(_ preparation: Preparation) throws -> (
        instruction: Instruction, payer: Address, configuration: Configuration, blockhash: GetLatestBlockhash.Response
    ) {
        guard case .local(let instructions, let payer, let configuration, let blockhash) = preparation.source,
              let instruction = instructions.first else {
            Issue.record("Expected native transfer construction details")
            throw ValidationError.invalidTransaction
        }
        return (instruction, payer, configuration, blockhash)
    }
}
