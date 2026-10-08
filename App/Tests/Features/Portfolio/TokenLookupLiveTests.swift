import Portfolio
import RPC
import Testing
import Transactions

/// Verifies live mint lookups through public mainnet RPC, which every provider choice supports.
struct TokenLookupLiveTests {
    /// Looks up an SPL token and a Token-2022 token without reading wallets or submitting transactions.
    ///
    /// - Throws: An RPC, validation, or lookup error.
    @Test(.timeLimit(.minutes(1)))
    func `Live lookups read on-chain names for both token programs`() async throws {
        let portfolio = Portfolio(rpc: Solana(network: .mainnet))

        let bonk = try await portfolio.token(at: Address("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"))
        let pyusd = try await portfolio.token(at: Address("2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"))

        #expect(bonk.token.program == .token)
        #expect(bonk.token.decimals == 5)
        #expect(bonk.token.name == "Bonk")
        #expect(pyusd.token.program == .token2022)
        #expect(pyusd.token.decimals == 6)
        #expect(pyusd.token.name == "PayPal USD")
        #expect(bonk.logo == nil && pyusd.logo == nil)
    }
}
