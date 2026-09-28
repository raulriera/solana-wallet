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
        #expect(preparation.tips.isEmpty)
        #expect(preparation.network == .devnet)
        #expect(preparation.fee.value == 5_000)
        #expect(preparation.simulation.value.error == nil)
        #expect(preparation.simulation.value.replacementBlockhash == nil)
        #expect(preparation.simulation.context.slot >= preparation.source.context.slot)
        #expect(preparation.transaction.instructions.count == 2)
        #expect(preparation.transaction.signatures.allSatisfy { $0.allSatisfy { $0 == 0 } })
        try await PreparationValidator(rpc: rpc).validate(preparation)
    }

    /// Verifies a reviewed token debit or service payment cannot disagree with the signed message.
    ///
    /// - Parameter altersTip: Whether to add an unencoded tip instead of changing the token debit.
    @Test("token review changes are rejected before signing", .timeLimit(.minutes(2)), arguments: [false, true])
    func alteredTokenReviewIsRejected(altersTip: Bool) async throws {
        let rpc = try devnetRPC()
        let recipient = try Address(await Wallet().address(for: Wallet().recoveryPhrase()))
        let original = try await preparation(for: Self.examples[0], to: recipient, rpc: rpc)
        guard case .token(let transfer, _, let configuration, let blockhash) = original.source else {
            Issue.record("Expected a locally constructed token preparation")
            return
        }
        let altered = try TokenTransfer(sender: transfer.sender, recipient: transfer.recipient,
            mint: transfer.mint, source: transfer.source, destination: nil, amount: altersTip ? 1 : 2)
        let tips = altersTip ? [try Transfer(sender: transfer.sender, recipient: recipient, lamports: 5_000)] : []
        let review = Preparation(source: .token(altered, tips, configuration, blockhash),
            signer: original.signer, transaction: original.transaction, network: original.network,
            fee: original.fee, simulation: original.simulation)

        await #expect(throws: PreparationValidator.Failure.messageMismatch) {
            try await PreparationValidator(rpc: rpc).validate(review)
        }
    }

    /// Verifies default source-account discovery reports an unfunded wallet's missing token account.
    ///
    /// - Parameter example: A real mint belonging to one of the supported token programs.
    @Test("devnet token preparation reports a missing sender account",
          .timeLimit(.minutes(1)), arguments: examples)
    func missingSourceIsReported(_ example: Example) async throws {
        let rpc = try devnetRPC()
        let sender = try Address(await Wallet().address(for: Wallet().recoveryPhrase()))
        let coordinator: any TransactionCoordinating = try TransactionCoordinator(
            rpc: rpc, store: KeychainStore(service: "widgetsTests.TokenPreparation")
        )
        let configuration = try Configuration(priorityFeeLamports: 0, computeUnitLimit: 200_000,
                                               loadedAccountsDataSizeLimit: 1_048_576)

        await #expect {
            try await coordinator.prepareTokenTransfer(mint: Address(example.mint), amount: 1,
                from: sender, to: sender, configuration: configuration)
        } throws: { error in
            guard case Preparer.Failure.missingAccount(let address) = error else { return false }
            return address.value != example.mint && address != sender
        }
    }

    /// Builds an unsigned review from a real devnet account without signing or broadcasting.
    ///
    /// - Parameters:
    ///   - example: The public mint and source account to read.
    ///   - recipient: The unfunded wallet whose receiving account must be created.
    ///   - rpc: The real devnet client.
    /// - Returns: A one-unit preparation through the app's coordinator contract.
    /// - Throws: A missing live fixture, preparation, or cancellation error.
    private func preparation(for example: Example, to recipient: Address, rpc: any RPC) async throws -> Preparation {
        let sourceAddress = try Address(example.source)
        let state = try await rpc.send(GetMultipleAccounts(addresses: [sourceAddress.value]))
        let account = try #require(state.value.first ?? nil)
        let source = try TokenAccount(address: sourceAddress, programOwner: Address(account.owner), data: account.data)
        let coordinator: any TransactionCoordinating = try TransactionCoordinator(
            rpc: rpc, store: KeychainStore(service: "widgetsTests.TokenPreparation")
        )
        let configuration = try Configuration(priorityFeeLamports: 0, computeUnitLimit: 200_000,
                                               loadedAccountsDataSizeLimit: 1_048_576)
        if example.program == .token2022 {
            return try await coordinator.prepareTokenTransfer(mint: Address(example.mint), amount: 1,
                from: source.owner, to: recipient, configuration: configuration)
        }
        return try await coordinator.prepareTokenTransfer(mint: Address(example.mint), amount: 1,
            from: source.owner, to: recipient, configuration: configuration, source: sourceAddress, memo: nil)
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
