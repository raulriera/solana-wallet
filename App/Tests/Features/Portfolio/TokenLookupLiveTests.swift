import Foundation
import Portfolio
import RPC
import Testing
import Transactions

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct TokenLookupLiveTests {
    private let temporary = IsolatedDirectory()

    @Test
    func `Live lookups read on-chain names for both token programs`() async throws {
        let directory = temporary.url
        let portfolio = Portfolio(rpc: SolanaRPC(network: .mainnet),
                                  tokenListDirectory: directory.appending(path: "TokenLists"), cacheDirectory: directory)

        async let bonkLookup = portfolio.token(at: Address("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
        async let pyusdLookup = portfolio.token(at: Address("2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"))
        let (bonk, pyusd) = try await (bonkLookup, pyusdLookup)

        #expect(bonk.mint.program == .token)
        #expect(bonk.mint.decimals == 5)
        #expect(bonk.mint.metadata?.name == "Bonk")
        #expect(pyusd.mint.program == .token2022)
        #expect(pyusd.mint.decimals == 6)
        #expect(pyusd.mint.metadata?.name == "PayPal USD")
        #expect(bonk.logo == nil)
        #expect(pyusd.logo == nil)
    }
}
