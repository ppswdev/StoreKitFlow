import Foundation
import Testing
@testable import StoreKitFlow

@Test func rejectsDuplicateIDs() {
    let config = StoreConfiguration(products: [.init("a", kind: .nonConsumable), .init("a", kind: .nonConsumable)])
    #expect(throws: StoreFailure.self) { try config.validate() }
}
