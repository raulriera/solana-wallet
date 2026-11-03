import CryptoKit
import Foundation
import RPC
import Transactions
@testable import widgets
import Vault
import Wallet

struct SigningFixture {
    let recovery: Recovery
    let account: widgets.Account
    let oneTime: OneTimeAccount
    var transfer: Instruction
    var configuration: Configuration
    let network: Network
    let inspection: Transaction
    var message: Data
    var blockhash: GetLatestBlockhash.Response
    var fee: GetFeeForMessage.Response
    var simulation: SimulateTransaction.Response

    var preparation: Preparation {
        Preparation(source: .local([transfer], transfer.accounts[0].address, configuration, blockhash), signer: transfer.accounts[0].address,
                    transaction: Transaction(message: message, lifetimeSpecifier: inspection.lifetimeSpecifier,
                                             accounts: inspection.accounts, requests: inspection.requests,
                                             instructions: inspection.instructions, signatures: inspection.signatures),
                    network: network, fee: fee, simulation: simulation)
    }

    init() throws {
        let base = try PreparationFixture.preparation()
        let source = try PreparationFixture.source(base)
        recovery = Recovery(
            phrase: try RecoveryPhrase("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
            passphrase: "TREZOR"
        )
        transfer = try SystemProgram.transfer(from: Address("8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"), to: source.instruction.accounts[1].address, lamports: 1)
        account = Account(id: UUID(), recoveryID: UUID(), address: transfer.accounts[0].address, path: try DerivationPath("m/44'/501'/1'/0'"))
        oneTime = try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 7, count: 32)))
        configuration = source.configuration
        network = base.network
        blockhash = source.blockhash
        fee = base.fee
        simulation = base.simulation
        message = try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: blockhash.value.blockhash,
                                               configuration: configuration)
        inspection = try TransactionDecoder().decode(message + Data(repeating: 0, count: 64))
    }

    func preparation(for address: Address) throws -> Preparation {
        let instruction = try SystemProgram.transfer(from: address, to: transfer.accounts[1].address, lamports: 1)
        let message = try MessageBuilder().message(instructions: [instruction], payer: address,
            recentBlockhash: blockhash.value.blockhash, configuration: configuration)
        let transaction = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
        return Preparation(source: .local([instruction], address, configuration, blockhash),
            signer: address, transaction: transaction, network: network, fee: fee, simulation: simulation)
    }
}
