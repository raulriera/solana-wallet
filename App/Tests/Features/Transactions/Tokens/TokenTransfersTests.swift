import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenTransfersTests {
    @Test(arguments: TokenProgram.allCases, [
        (lamports: UInt64(890_880), topUp: UInt64(1_209_120)),
        (lamports: 2_100_000, topUp: 0),
        (lamports: 3_000_000, topUp: 0),
    ])
    func `Prefunded associated accounts need only their missing rent`(
        program: TokenProgram, funding: (lamports: UInt64, topUp: UInt64)
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .funded(funding.lamports))

        let result = try await TokenTransfers(rpc: http.client).transfer(
            mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)

        #expect(result.transfer.createsDestination)
        #expect(result.rent == funding.topUp)
        #expect(result.slot == 101)
        let instructions = try result.transfer.instructions()
        let creation = try #require(instructions.first)
        #expect(instructions.count == 2)
        #expect(creation.program.value == "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        #expect(creation.data == Data([1]))
    }

    @Test(arguments: [(TokenProgram.token, 165), (.token2022, 170)])
    func `Absent associated accounts are created with their full rent`(
        program: TokenProgram, allocationSize: Int
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .absent)

        let result = try await TokenTransfers(rpc: http.client).transfer(
            mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)

        #expect(result.transfer.createsDestination)
        #expect(result.rent == 2_100_000)
        #expect(try result.transfer.instructions().first?.data == Data([1]))
        let requests = await http.requests
        let rentRequest = try #require(requests.first { try $0.rpcMethod == "getMinimumBalanceForRentExemption" })
        #expect(try rentRequest.rpcParameters.first as? Int == allocationSize)
        for request in requests {
            #expect(try (request.rpcParameters.last as? [String: Any])?["commitment"] as? String == "finalized")
        }
    }

    @Test(arguments: TokenProgram.allCases)
    func `Initialized associated accounts need no creation or rent`(program: TokenProgram) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .initialized)

        let result = try await TokenTransfers(rpc: http.client).transfer(
            mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)

        #expect(!result.transfer.createsDestination)
        #expect(result.rent == 0)
        let instructions = try result.transfer.instructions()
        #expect(instructions.count == 1)
        #expect(instructions.first?.program.value == program.rawValue)
        #expect(try await http.requests.allSatisfy { try $0.rpcMethod != "getMinimumBalanceForRentExemption" })
    }

    @Test(arguments: TokenProgram.allCases)
    func `Token account recipients receive directly with no creation or rent`(program: TokenProgram) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .absent, recipient: .tokenAccount)

        let result = try await TokenTransfers(rpc: http.client).transfer(
            mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.tokenAccount, source: fixture.source)

        #expect(result.transfer.destination == fixture.tokenAccount)
        #expect(result.transfer.recipient == fixture.recipient)
        #expect(!result.transfer.createsDestination)
        #expect(result.rent == 0)
        #expect(try result.transfer.instructions().count == 1)
        let methods = try await http.requests.map { try $0.rpcMethod }
        #expect(methods.filter { $0 == "getMultipleAccounts" }.count == 1)
        #expect(!methods.contains("getMinimumBalanceForRentExemption"))
    }

    @Test(arguments: TokenProgram.allCases, [
        (recipient: TokenTransferResponses.Recipient.mint, error: TokenError.invalidAccount),
        (recipient: .otherMintTokenAccount, error: .accountMismatch), (recipient: .program, error: .invalidAccount),
    ])
    func `Mint, other-mint token account, and program recipients are rejected`(
        program: TokenProgram, rejection: (recipient: TokenTransferResponses.Recipient, error: TokenError)
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .absent, recipient: rejection.recipient)
        let address = rejection.recipient == .mint ? fixture.mint.address : fixture.recipient

        await #expect(throws: rejection.error) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: fixture.mint, amount: 1, from: fixture.sender, to: address, source: fixture.source)
        }
    }

    @Test(arguments: [TokenTransferResponses.Recipient.absent, .programOwned])
    func `Recipients outside the token programs receive at their associated account`(
        recipient: TokenTransferResponses.Recipient
    ) async throws {
        let fixture = try TokenTransferResponses(program: .token)
        let http = try fixture.http(destination: .absent, recipient: recipient)

        let result = try await TokenTransfers(rpc: http.client).transfer(
            mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)

        #expect(result.transfer.destination == fixture.tokenAccount)
        #expect(result.transfer.createsDestination)
    }

    @Test(arguments: TokenProgram.allCases, [
        (destination: TokenTransferResponses.Destination.unsupportedOwner, error: TokenError.unsupportedProgram),
        (destination: .nonemptySystem, error: .invalidAccount), (destination: .executable, error: .invalidAccount),
    ])
    func `Invalid destination accounts remain rejected`(
        program: TokenProgram, rejection: (destination: TokenTransferResponses.Destination, error: TokenError)
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: rejection.destination)

        await #expect(throws: rejection.error) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)
        }

        #expect(await http.requests.count == 1)
    }

    @Test(arguments: TokenProgram.allCases)
    func `A recipient whose token account another address controls is rejected`(program: TokenProgram) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .otherOwner)

        await #expect(throws: TokenError.accountMismatch) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)
        }
    }

    @Test(arguments: [
        (TokenProgram.token2022, reviewedProgram: TokenProgram.token2022, reviewedDecimals: UInt8(9)),
        (.token2022, reviewedProgram: .token, reviewedDecimals: 6),
        (.token, reviewedProgram: .token2022, reviewedDecimals: 6),
    ])
    func `A mint whose program or decimals differ from the reviewed mint's is rejected`(
        program: TokenProgram, reviewedProgram: TokenProgram, reviewedDecimals: UInt8
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: .initialized)
        let reviewed = Mint.fixture(fixture.mint.address.value, program: reviewedProgram, decimals: reviewedDecimals)

        await #expect(throws: TokenError.accountMismatch) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: reviewed, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)
        }

        #expect(await http.requests.count == 1)
    }

    @Test
    func `Prefunding cannot bypass a Token-2022 default frozen account state`() async throws {
        let fixture = try TokenTransferResponses(program: .token2022)
        let http = try fixture.http(destination: .funded(890_880), defaultFrozen: true)

        await #expect(throws: TokenError.frozenAccount) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)
        }
    }
}
