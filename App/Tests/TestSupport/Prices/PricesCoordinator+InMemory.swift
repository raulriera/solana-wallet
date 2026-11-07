@testable import widgets

extension PricesCoordinator {
    static func inMemory(_ prices: PriceStore = .inMemory()) -> PricesCoordinator {
        PricesCoordinator(prices: prices, connection: CustomPriceConnection(prices: prices) { _ in nil })
    }
}
