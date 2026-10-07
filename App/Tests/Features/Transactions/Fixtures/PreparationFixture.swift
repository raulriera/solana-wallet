import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// A public Solana SDK message fixture with typed ledger observations.
enum PreparationFixture {
    /// Creates explicit resource limits matching Solana's independent V1 message fixture.
    ///
    /// - Returns: A 5,000-lamport priority fee and bounded execution resources.
    /// - Throws: A validation error if fixture constants violate the resource bounds.
    static func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                          loadedAccountsDataSizeLimit: 65_536, heapSize: 65_536)
    }

    /// Constructs review data through the app's internal review type.
    ///
    /// The message comes from the same independently generated Solana SDK example
    /// described in `references/transactions.md`; no wallet secrets are used.
    ///
    /// - Parameters:
    ///   - fee: The node's total fee, or `nil` if it couldn't determine the fee.
    ///   - error: An execution failure, or `nil` if simulation succeeded.
    /// - Returns: A typed fixture for the injected provider and service assertions.
    /// - Throws: A validation error if the fixture's public addresses are invalid.
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

    /// Extracts native construction details, failing the test if it received external data.
    ///
    /// - Parameter preparation: The review whose native source to inspect.
    /// - Returns: The original transfer, configuration, and blockhash observation.
    /// - Throws: A test failure if the review wasn't constructed from a SOL transfer.
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
