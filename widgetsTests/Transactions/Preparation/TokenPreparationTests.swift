import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Exercises account discovery and token preparation through real devnet RPC.
struct TokenPreparationTests {
    /// Verifies both token programs produce a review with a checked transfer and new recipient account.
    ///
    /// These public devnet accounts are read and simulated without signatures;
    /// this test has no recovery material for them and never broadcasts.
    ///
    /// - Parameter example: A funded public account from either first-party token program.
    @Test("devnet token preparation simulates the debit and recipient account creation",
          .timeLimit(.minutes(2)), arguments: examples)
    func tokenPreparationReturnsReview(_ example: Example) async throws {
        let rpc = try devnetRPC()
        let recipient = try Address(await Wallet().address(for: Wallet().recoveryPhrase()))
        let preparation = try await preparation(for: example, to: recipient, rpc: rpc)

        let transfer = try #require(preparation.tokenTransfer)
        #expect(transfer.mint.program == example.program)
        #expect(transfer.mint.address.value == example.mint)
        #expect(transfer.amount == 1)
        #expect(transfer.recipient == recipient)
        #expect(transfer.source.address.value == example.source)
        #expect(transfer.createsDestination)
        #expect(transfer.expectedFee == nil)
        let rent = try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: example.program == .token ? 165 : 170))
        #expect(preparation.destinationAccountRent == rent)
        #expect(rent > 0)
        #expect(preparation.tips.isEmpty)
        #expect(preparation.network == .devnet)
        #expect(preparation.fee == 5_000)
        #expect(preparation.diagnostics.value.error == nil)
        #expect(preparation.diagnostics.value.replacementBlockhash == nil)
        #expect(preparation.transaction.instructions.count == 2)
        #expect(preparation.transaction.signatures.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    /// Verifies a real existing ATA doesn't add another account-creation deposit.
    @Test("devnet token preparation reports zero rent for an existing destination", .timeLimit(.minutes(2)))
    func existingDestinationHasNoCreationRent() async throws {
        let rpc = try devnetRPC()
        let preparation = try await preparation(for: Self.examples[1], to: nil, rpc: rpc)

        #expect(preparation.tokenTransfer?.createsDestination == false)
        #expect(preparation.destinationAccountRent == 0)
        #expect(preparation.transaction.instructions.count == 1)
        #expect(preparation.diagnostics.value.error == nil)
    }

    /// Verifies default source-account discovery reports an unfunded wallet's missing token account.
    ///
    /// - Parameter example: A real mint belonging to one of the supported token programs.
    @Test("devnet token preparation reports a missing sender account",
          .timeLimit(.minutes(1)), arguments: examples)
    func missingSourceIsReported(_ example: Example) async throws {
        let rpc = try devnetRPC()
        let sender = try Address(await Wallet().address(for: Wallet().recoveryPhrase()))
        let coordinator = try TransactionCoordinator(
            rpc: rpc, store: KeychainStore(service: "widgetsTests.TokenPreparation")
        )

        await #expect {
            try await coordinator.transfer(1, token: Address(example.mint),
                using: Account(id: UUID(), address: sender), to: sender)
        } throws: { error in
            guard case TokenTransfers.Failure.missingAccount(let address) = error else { return false }
            return address.value != example.mint && address != sender
        }
    }

    /// Builds an unsigned review from a real devnet account without signing or broadcasting.
    ///
    /// - Parameters:
    ///   - example: The public mint and source account to read.
    ///   - recipient: The receiving wallet, or `nil` for the source account's owner.
    ///   - rpc: The real devnet client.
    /// - Returns: A one-unit preparation through the app's coordinator contract.
    /// - Throws: A missing live fixture, preparation, or cancellation error.
    private func preparation(for example: Example, to recipient: Address?, rpc: any RPC) async throws -> Simulation {
        let sourceAddress = try Address(example.source)
        let state = try await rpc.send(GetMultipleAccounts(addresses: [sourceAddress.value]))
        let account = try #require(state.value.first ?? nil)
        let source = try TokenAccount(address: sourceAddress, programOwner: Address(account.owner), data: account.data)
        let coordinator = try TransactionCoordinator(
            rpc: rpc, store: KeychainStore(service: "widgetsTests.TokenPreparation")
        )
        return try await coordinator.transfer(1, token: Address(example.mint),
            using: Account(id: UUID(), address: source.owner), to: recipient ?? source.owner,
            source: example.program == .token ? sourceAddress : nil)
    }

    /// Creates a real devnet client using the test runner's ignored local configuration.
    ///
    /// - Returns: The current Helius RPC implementation on devnet.
    /// - Throws: A test prerequisite failure when the API key is missing.
    private func devnetRPC() throws -> HeliusRPC {
        let key = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"])
        try #require(!key.isEmpty && !key.hasPrefix("$("))
        return HeliusRPC(apiKey: key, network: .devnet)
    }

    /// Public, read-only devnet examples observed on September 28, 2026.
    struct Example: Sendable {
        let program: TokenProgram
        let mint: String
        let source: String
    }

    static let examples = [
        Example(program: .token, mint: "So11111111111111111111111111111111111111112",
                source: "6BsAxBZEsyJk8jTK6Fs6F1FAdJ9AHyRYmGPbEL9tDKfU"),
        Example(program: .token2022, mint: "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP",
                source: "CHFMpxRemf71mraJJMwkLkAhW962TRCKwhrgz5ADH1on"),
    ]
}
