import Foundation
import Testing

extension Data {
    func jsonObject() throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: self) as? NSDictionary)
    }
}
