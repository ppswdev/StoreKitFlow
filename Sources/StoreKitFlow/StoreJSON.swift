import Foundation

/// Stable, explicit exports. Does no I/O. Identifiers and Decimal values remain strings.
/// Raw StoreKit JSON, account tokens and signed evidence are intentionally excluded.
public enum StoreJSON {
    public static func products(_ values: [ProductDetails]) throws -> Data {
        try encode(Envelope(schemaVersion: 1, items: values.map(ProductExport.init)))
    }
    public static func transactions(_ values: [TransactionDetails]) throws -> Data {
        try encode(Envelope(schemaVersion: 1, items: values.map(TransactionExport.init)))
    }
    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    private struct Envelope<T: Encodable>: Encodable { let schemaVersion: Int; let items: [T] }
    private struct OfferExport: Encodable {
        let id, type, price, displayPrice, periodUnit, paymentMode, eligibility: String
        let periodValue, periodCount: Int
        init(_ o: OfferDetails) {
            id = o.id; type = o.type; price = NSDecimalNumber(decimal: o.price).stringValue
            displayPrice = o.displayPrice; periodUnit = o.periodUnit; paymentMode = o.paymentMode
            eligibility = o.eligibility.rawValue; periodValue = o.periodValue; periodCount = o.periodCount
        }
    }
    private struct ProductExport: Encodable {
        let id, kind, rawType, displayName, description, price, displayPrice: String
        let currencyCode, groupID, periodUnit: String?
        let periodValue: Int?
        let familyShareable: Bool
        let offers: [OfferExport]
        let fetchedAt: Date
        init(_ p: ProductDetails) {
            id = p.id; kind = p.kind.rawValue; rawType = p.rawType; displayName = p.displayName
            description = p.description; price = NSDecimalNumber(decimal: p.price).stringValue
            displayPrice = p.displayPrice; currencyCode = p.currencyCode; groupID = p.groupID
            periodUnit = p.periodUnit; periodValue = p.periodValue; familyShareable = p.familyShareable
            offers = p.offers.map(OfferExport.init); fetchedAt = p.fetchedAt
        }
    }
    private struct TransactionExport: Encodable {
        let id, originalID, productID, kind, bundleID, environment, ownership: String
        let offerType, offerPaymentMode, revocationType, revocationPercentage: String?
        let purchaseDate, signedDate: Date
        let expirationDate, revocationDate: Date?
        let quantity: Int
        let isUpgraded: Bool
        init(_ t: TransactionDetails) {
            id = t.id; originalID = t.originalID; productID = t.productID; kind = t.kind.rawValue
            bundleID = t.bundleID; environment = t.environment; ownership = t.ownership.rawValue
            offerType = t.offerType; offerPaymentMode = t.offerPaymentMode; revocationType = t.revocationType
            revocationPercentage = t.revocationPercentage.map { NSDecimalNumber(decimal: $0).stringValue }
            purchaseDate = t.purchaseDate; signedDate = t.signedDate; expirationDate = t.expirationDate
            revocationDate = t.revocationDate; quantity = t.quantity; isUpgraded = t.isUpgraded
        }
    }
}
