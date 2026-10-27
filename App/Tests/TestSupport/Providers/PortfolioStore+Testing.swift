@testable import RPC
@testable import widgets

extension PortfolioStore {
    /// Portfolios that read every network through one service, over unread currency and provider settings.
    /// - Parameter service: The service that every network's portfolios read through.
    /// - Returns: Portfolios whose observations, refreshes, and token-list changes reach the service.
    static func serving(_ service: Service) -> PortfolioStore {
        PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                       providers: .inMemory()) { _, _ in service }
    }
}
