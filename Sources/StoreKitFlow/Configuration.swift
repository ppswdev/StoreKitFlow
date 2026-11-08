import Foundation
import StoreKit

public enum ProductKind: String, Codable, Sendable, CaseIterable {
    case consumable, nonConsumable, autoRenewable, nonRenewable, unsupported
}
public enum Access: String, Codable, Sendable { case unknown, inactive, active }
public enum SubscriptionState: String, Codable, Sendable {
    case subscribed, expired, inGracePeriod, inBillingRetryPeriod, revoked, unknown
}
public enum Ownership: String, Codable, Sendable { case purchased, familyShared, unknown }

public struct Term: Codable, Sendable, Equatable {
    public enum Unit: String, Codable, Sendable { case day, month, year }
    public let value: Int
    public let unit: Unit
    public init(_ value: Int, _ unit: Unit) { self.value = value; self.unit = unit }
    public func end(from date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let component: Calendar.Component = switch unit { case .day: .day; case .month: .month; case .year: .year }
        return calendar.date(byAdding: component, value: value, to: date)
    }
}
public struct ProductDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ProductKind
    public let entitlements: Set<String>
    public let groupID: String?
    public let term: Term?
    public let stacks: Bool
    public let credits: Int
    public init(_ id: String, kind: ProductKind, entitlements: Set<String> = [],
                groupID: String? = nil, term: Term? = nil, stacks: Bool = false, credits: Int = 1) {
        self.id = id; self.kind = kind; self.entitlements = entitlements; self.groupID = groupID
        self.term = term; self.stacks = stacks; self.credits = credits
    }
}
public struct StoreConfiguration: Sendable, Equatable {
    public let products: [ProductDefinition]
    public let acceptsFamilySharing: Bool
    public let storageURL: URL
    public let retryInterval: TimeInterval
    public init(products: [ProductDefinition], acceptsFamilySharing: Bool = true,
                storageURL: URL = StoreConfiguration.defaultStorageURL, retryInterval: TimeInterval = 30) {
        self.products = products; self.acceptsFamilySharing = acceptsFamilySharing
        self.storageURL = storageURL; self.retryInterval = retryInterval
    }
    public static var defaultStorageURL: URL {
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "StoreKitFlow-Unbundled")
            .appending(path: "StoreKitFlow/ledger.json")
    }
    public func validate() throws {
        guard !products.isEmpty, Set(products.map(\.id)).count == products.count,
              products.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), retryInterval.isFinite, retryInterval >= 1 else {
            throw StoreFailure(.configuration, "商品 ID 不能为空或重复，重试间隔至少 1 秒")
        }
        for product in products {
            guard product.kind != .unsupported, product.credits > 0 else { throw StoreFailure(.configuration, "不支持的商品配置：\(product.id)") }
            if product.kind == .nonRenewable && (product.term?.value ?? 0) <= 0 {
                throw StoreFailure(.configuration, "非续订商品必须配置有效期限：\(product.id)")
            }
            if product.kind == .consumable && !product.entitlements.isEmpty {
                throw StoreFailure(.configuration, "消耗品通过账本交付，不直接授予持久权益")
            }
        }
    }
}
public struct StoreFailure: Error, LocalizedError, Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case configuration, notStarted, productUnavailable, paymentsNotAllowed, operationInProgress
        case verificationFailed, deliveryFailed, persistenceFailed, presentationUnavailable
        case unsupportedCapability, offerInvalid, network, system, cancelled
    }
    public let code: Code
    public let message: String
    public var errorDescription: String? { message }
    public init(_ code: Code, _ message: String) { self.code = code; self.message = message }
    static func wrap(_ error: any Error) -> StoreFailure {
        if let failure = error as? StoreFailure { return failure }
        if error is CancellationError { return .init(.cancelled, "操作已中断；已发生的支付仍会继续核对") }
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled: return .init(.cancelled, "用户取消了系统操作")
            case .networkError: return .init(.network, storeError.localizedDescription)
            case .notAvailableInStorefront: return .init(.productUnavailable, storeError.localizedDescription)
            default: return .init(.system, storeError.localizedDescription)
            }
        }
        if let purchaseError = error as? Product.PurchaseError {
            let code: Code = switch purchaseError {
            case .purchaseNotAllowed: .paymentsNotAllowed
            case .productUnavailable: .productUnavailable
            case .invalidQuantity: .configuration
            case .ineligibleForOffer, .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature, .missingOfferParameters: .offerInvalid
            default: .system
            }
            return .init(code, purchaseError.localizedDescription)
        }
        return .init(error is URLError ? .network : .system, error.localizedDescription)
    }
}
