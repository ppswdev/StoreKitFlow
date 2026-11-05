import Foundation
import Testing
import StoreKitFlow

@Test func decimalExportIsLosslessAndPreservesOrdering() throws {
    let precise = try #require(Decimal(string: "1234567890.1234567890123456789"))
    let product = ProductDetails(id: "sku", kind: .consumable, rawType: "Consumable", displayName: "日元",
        description: "", price: precise, displayPrice: "￥100", currencyCode: "JPY")
    let json = try #require(String(data: StoreJSON.products([product]), encoding: .utf8))
    #expect(json.contains("\"price\" : \"1234567890.1234567890123456789\""))
    #expect(json.contains("\"schemaVersion\" : 1"))
}
@Test func transactionExportDoesNotLeakEvidenceAndKeepsLargeIDs() throws {
    let transaction = TransactionDetails(id: "18446744073709551615", productID: "sku", kind: .nonConsumable,
        appAccountToken: UUID(), rawJSON: Data("private-raw-payload".utf8), signedJWS: "private-signed-evidence")
    let json = try #require(String(data: StoreJSON.transactions([transaction]), encoding: .utf8))
    #expect(json.contains("\"18446744073709551615\""))
    #expect(!json.contains("private-"))
    #expect(!json.contains("appAccountToken"))
    #expect(!json.contains("signedJWS"))
}
