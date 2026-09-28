import Foundation
import RPC
import Transactions
@testable import widgets
import Vault
import Wallet

/// Mutable test inputs that expose attempts to change immutable review data.
struct SigningFixture {
    let recovery: Recovery
    var transfer: Instruction
    var configuration: Configuration
    var network: Network
    let inspection: Transaction
    var message: Data
    var blockhash: GetLatestBlockhash.Response
    var fee: GetFeeForMessage.Response
    var simulation: SimulateTransaction.Response

    /// The review value constructed through the internal initializer.
    var preparation: Preparation {
        Preparation(source: .local([transfer], transfer.accounts[0].address, configuration, blockhash), signer: transfer.accounts[0].address,
                    transaction: Transaction(message: message, lifetimeSpecifier: inspection.lifetimeSpecifier,
                                             accounts: inspection.accounts, requests: inspection.requests,
                                             instructions: inspection.instructions, signatures: inspection.signatures),
                    network: network, fee: fee, simulation: simulation)
    }

    /// Creates a preparation for a published phrase with a nondefault passphrase and path.
    ///
    /// - Throws: An error if the public fixture or its message can't be constructed.
    init() throws {
        let base = try PreparationFixture.preparation()
        let source = try PreparationFixture.source(base)
        recovery = Recovery(
            phrase: try RecoveryPhrase("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
            passphrase: "TREZOR", path: try DerivationPath("m/44'/501'/1'/0'")
        )
        transfer = try SystemProgram.transfer(from: Address("8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"), to: source.instruction.accounts[1].address, lamports: 1)
        configuration = source.configuration
        network = base.network
        blockhash = source.blockhash
        fee = base.fee
        simulation = base.simulation
        message = try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: blockhash.value.blockhash,
                                               configuration: configuration)
        inspection = try TransactionDecoder().decode(message + Data(repeating: 0, count: 64))
    }
}
