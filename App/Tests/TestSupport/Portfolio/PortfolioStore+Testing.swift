@testable import RPC
@testable import widgets

extension PortfolioStore {
    static func serving(_ service: Service) -> PortfolioStore {
        PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                       rpcStore: .inMemory(), priceChoice: .inMemory()) { _, _ in service }
    }
}
