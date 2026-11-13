import Encoding
import Foundation
import Portfolio
import RPC
import Testing
@testable import Transactions

struct TokenLookupTests {
    enum Refusal: CaseIterable {
        case missing
        case wallet
        case tokenAccount
        case nft
    }

    @Test
    func `A pasted mint shows its on-chain name and symbol`() async throws {
        let mint = try Address(usdcMint)
        let metadataAccount = try TokenMetadata.metaplexAccount(for: mint)
        let http = LookupResponses(accounts: [
            usdcMint: mintAccount(decimals: 6, supply: 1_000),
            metadataAccount.value: Account(owner: metaplexProgram, lamports: 1, executable: false,
                                           data: metaplexData(mint: mint, name: "USD Coin", symbol: "USDC")),
        ])

        let preview = try await lookupPortfolio(http.client).token(at: mint)

        #expect(preview == TokenPreview(token: ListedToken(mint: mint, program: .token, decimals: 6,
                                                           symbol: "USDC", name: "USD Coin"), logo: nil))
        #expect(await http.requests == [[usdcMint, metadataAccount.value]])
    }

    @Test
    func `A mint without metadata has no name or symbol`() async throws {
        let mint = try Address(usdcMint)
        let http = LookupResponses(accounts: [usdcMint: mintAccount(decimals: 6, supply: 1_000)])

        let preview = try await lookupPortfolio(http.client).token(at: mint)

        #expect(preview.token == ListedToken(mint: mint, program: .token, decimals: 6, symbol: nil, name: nil))
    }

    @Test(arguments: Refusal.allCases, [false, true])
    func `Addresses that aren't fungible token mints are refused`(_ refusal: Refusal, helius: Bool) async throws {
        let mint = try Address(usdcMint)
        let account: Account? = switch refusal {
        case .missing: nil
        case .wallet: Account(owner: "11111111111111111111111111111111", lamports: 1, executable: false, data: Data())
        case .tokenAccount:
            Account(owner: TokenProgram.token.rawValue, lamports: 1, executable: false,
                    data: tokenAccountData(mint: mint, owner: try Address(testWallet), units: 5, program: .token))
        case .nft: mintAccount(decimals: 0, supply: 1)
        }
        let http = LookupResponses(accounts: account.map { [usdcMint: $0] } ?? [:])

        let rpc: any RPC = helius ? http.heliusClient : http.client

        await #expect(throws: refusal == .nft ? TokenLookupError.nonFungible : .notToken) {
            try await lookupPortfolio(rpc).token(at: mint)
        }
    }

    @Test(arguments: [false, true])
    func `A provider with logo copies adds the logo to the preview`(logoFails: Bool) async throws {
        let mint = try Address(usdcMint)
        let http = LookupResponses(accounts: [usdcMint: mintAccount(decimals: 6, supply: 1_000)]) { _ in
            if logoFails { throw URLError(.notConnectedToInternet) }
            return [usdcMint: "https://cdn.example.com/usdc.png"]
        }

        let preview = try await lookupPortfolio(http.heliusClient).token(at: mint)

        #expect(preview.logo == (logoFails ? nil : URL(string: "https://cdn.example.com/usdc.png")))
        #expect(preview.token.decimals == 6)
        #expect(await http.logoRequests == [[usdcMint]])
    }
}

private let metaplexProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"

private func lookupPortfolio(_ rpc: any RPC) -> Portfolio {
    Portfolio(rpc: rpc, tokenListDirectory: .temporaryDirectory, cacheDirectory: .temporaryDirectory)
}

private func mintAccount(decimals: UInt8, supply: UInt64) -> Account {
    var bytes = [UInt8](repeating: 0, count: 36)
    bytes.append(littleEndian: supply)
    bytes += [decimals, 1]
    bytes += [UInt8](repeating: 0, count: 36)
    return Account(owner: TokenProgram.token.rawValue, lamports: 1_461_600, executable: false, data: Data(bytes))
}

private func metaplexData(mint: Address, name: String, symbol: String) -> Data {
    func padded(_ text: String, to length: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(littleEndian: UInt32(length))
        return bytes + Array(text.utf8) + [UInt8](repeating: 0, count: length - text.utf8.count)
    }
    return Data([4] + [UInt8](repeating: 0, count: 32) + mint.bytes + padded(name, to: 32) + padded(symbol, to: 10))
}
