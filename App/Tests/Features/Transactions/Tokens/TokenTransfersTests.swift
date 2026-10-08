import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies destination classification and rent deposits through real RPC encoding and decoding.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenTransfersTests {
    /// SOL already at an unallocated ATA reduces its deposit without preventing idempotent creation.
    /// - Parameters:
    ///   - program: The token program governing the mint and transfer.
    ///   - funding: The existing balance and independently expected missing rent.
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

    /// An absent account still needs the full quoted deposit for its program's allocation size.
    /// - Parameters:
    ///   - program: The mint's token program.
    ///   - allocationSize: The expected account size, including Token-2022 immutable ownership.
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
    }

    /// A decoded token destination needs only the transfer, with no deposit lookup.
    /// - Parameter program: The mint's token program.
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

    /// Prefunding cannot turn another program's account or allocated/executable data into a creatable ATA.
    /// - Parameters:
    ///   - program: The mint's token program.
    ///   - destination: The invalid account observed at the canonical destination.
    @Test(arguments: TokenProgram.allCases, [
        TokenTransferResponses.Destination.unsupportedOwner, .nonemptySystem, .executable,
    ])
    func `Invalid destination accounts remain rejected`(
        program: TokenProgram, destination: TokenTransferResponses.Destination
    ) async throws {
        let fixture = try TokenTransferResponses(program: program)
        let http = try fixture.http(destination: destination)

        await #expect(throws: TokenError.self) {
            try await TokenTransfers(rpc: http.client).transfer(
                mint: fixture.mint, amount: 1, from: fixture.sender, to: fixture.recipient, source: fixture.source)
        }

        #expect(await http.requests.count == 2)
    }

    /// An unallocated prefunded address still uses the mint's rules for newly initialized accounts.
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
