import Foundation
import RPC
import Transactions
@testable import widgets
import Vault
import Wallet

/// Mutable test inputs that expose attempts to change immutable review data.
struct SigningFixture {
    let recovery: Recovery
    var transfer: Transfer
    var configuration: Configuration
    var network: Network
    let inspection: Transaction
    var message: Data
    var blockhash: GetLatestBlockhash.Response
    var fee: GetFeeForMessage.Response
    var simulation: SimulateTransaction.Response

    /// The review value constructed through the internal initializer.
    var preparation: Preparation {
        Preparation(source: .transfer(transfer, configuration, blockhash), signer: transfer.sender,
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
        transfer = try Transfer(sender: Address("8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"),
                                recipient: source.transfer.recipient, lamports: 1)
        configuration = source.configuration
        network = base.network
        blockhash = source.blockhash
        fee = base.fee
        simulation = base.simulation
        message = try MessageBuilder().message(for: transfer, recentBlockhash: blockhash.value.blockhash,
                                               configuration: configuration)
        inspection = try TransactionDecoder().decode(message + Data(repeating: 0, count: 64))
    }
}
