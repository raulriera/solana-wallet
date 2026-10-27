@testable import RPC
@testable import widgets

extension NetworkPortfolios {
    /// Portfolios that record settings changes and report any other use, over unread provider settings, for views
    /// that need the shared portfolios but never observe through them.
    static var unused: NetworkPortfolios {
        NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                          providers: .inMemory()) { _, _ in PortfolioChanges() }
    }
}
