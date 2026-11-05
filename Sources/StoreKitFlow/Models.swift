import Foundation

public struct OfferDetails: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let price: Decimal
    public let displayPrice: String
    public let periodValue: Int
    public let periodUnit: String
    public let periodCount: Int
    public let paymentMode: String
    public var eligibility: Eligibility
    public init(id: String, type: String, price: Decimal, displayPrice: String, periodValue: Int,
                periodUnit: String, periodCount: Int, paymentMode: String, eligibility: Eligibility) {
        self.id = id; self.type = type; self.price = price; self.displayPrice = displayPrice
        self.periodValue = periodValue; self.periodUnit = periodUnit; self.periodCount = periodCount
        self.paymentMode = paymentMode; self.eligibility = eligibility
    }
    public enum Eligibility: String, Codable, Sendable { case eligible, ineligible, unknown, requiresSignature }
}
/// Missing fields stay nil; raw JSON retains SDK fields not projected into this model.
public struct ProductDetails: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ProductKind
    public let rawType: String
    public let displayName: String
    public let description: String
    public let price: Decimal
    public let displayPrice: String
    public let currencyCode: String?
    public let familyShareable: Bool
    public let groupID: String?
    public let periodValue: Int?
    public let periodUnit: String?
    public let offers: [OfferDetails]
    public let rawJSON: Data
    public let fetchedAt: Date
    public init(id: String, kind: ProductKind, rawType: String, displayName: String, description: String,
                price: Decimal, displayPrice: String, currencyCode: String? = nil, familyShareable: Bool = false,
                groupID: String? = nil, periodValue: Int? = nil, periodUnit: String? = nil,
                offers: [OfferDetails] = [], rawJSON: Data = Data(), fetchedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.rawType = rawType; self.displayName = displayName
        self.description = description; self.price = price; self.displayPrice = displayPrice
        self.currencyCode = currencyCode; self.familyShareable = familyShareable; self.groupID = groupID
        self.periodValue = periodValue; self.periodUnit = periodUnit; self.offers = offers
        self.rawJSON = rawJSON; self.fetchedAt = fetchedAt
    }
}
public struct TransactionDetails: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var originalID: String
    public var productID: String
    public var kind: ProductKind
    public var bundleID: String
    public var environment: String
    public var purchaseDate: Date
    public var expirationDate: Date?
    public var revocationDate: Date?
    public var signedDate: Date
    public var quantity: Int
    public var ownership: Ownership
    public var isUpgraded: Bool
    public var appAccountToken: UUID?
    public var offerType: String?
    public var offerPaymentMode: String?
    public var revocationType: String?
    public var revocationPercentage: Decimal?
    public var rawJSON: Data
    public var signedJWS: String?
    public var key: String { "\(bundleID)|\(environment)|\(id)" }
    /// Signing the same refund payload again must not create another business compensation.
    public var revocationKey: String? {
        guard let revocationDate else { return nil }
        let percentage = revocationPercentage.map { NSDecimalNumber(decimal: $0).stringValue } ?? "100"
        return "\(key)|revoke|\(revocationDate.timeIntervalSince1970)|\(revocationType ?? "unknown")|\(percentage)"
    }
    public init(id: String, originalID: String? = nil, productID: String, kind: ProductKind,
                bundleID: String = "preview", environment: String = "xcode",
                purchaseDate: Date = Date(), expirationDate: Date? = nil, revocationDate: Date? = nil,
                signedDate: Date = Date(), quantity: Int = 1, ownership: Ownership = .purchased,
                isUpgraded: Bool = false, appAccountToken: UUID? = nil, offerType: String? = nil,
                offerPaymentMode: String? = nil, revocationType: String? = nil,
                revocationPercentage: Decimal? = nil, rawJSON: Data = Data(), signedJWS: String? = nil) {
        self.id = id; self.originalID = originalID ?? id; self.productID = productID; self.kind = kind
        self.bundleID = bundleID; self.environment = environment; self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate; self.revocationDate = revocationDate; self.signedDate = signedDate
        self.quantity = quantity; self.ownership = ownership; self.isUpgraded = isUpgraded
        self.appAccountToken = appAccountToken; self.offerType = offerType; self.offerPaymentMode = offerPaymentMode
        self.revocationType = revocationType; self.revocationPercentage = revocationPercentage
        self.rawJSON = rawJSON; self.signedJWS = signedJWS
    }
}
public struct SubscriptionDetails: Codable, Sendable, Equatable {
    public let groupID: String
    public let state: SubscriptionState
    public let transaction: TransactionDetails
    public let willAutoRenew: Bool?
    public let autoRenewPreference: String?
    public let gracePeriodExpirationDate: Date?
    public let renewalDate: Date?
    public let expirationReason: String?
    public let priceIncreaseStatus: String?
    public let renewalJSON: Data
    public let verified: Bool
    public init(groupID: String, state: SubscriptionState, transaction: TransactionDetails,
                willAutoRenew: Bool? = nil, autoRenewPreference: String? = nil,
                gracePeriodExpirationDate: Date? = nil, renewalDate: Date? = nil,
                expirationReason: String? = nil, priceIncreaseStatus: String? = nil,
                renewalJSON: Data = Data(), verified: Bool = true) {
        self.groupID = groupID; self.state = state; self.transaction = transaction
        self.willAutoRenew = willAutoRenew; self.autoRenewPreference = autoRenewPreference
        self.gracePeriodExpirationDate = gracePeriodExpirationDate; self.renewalDate = renewalDate
        self.expirationReason = expirationReason; self.priceIncreaseStatus = priceIncreaseStatus
        self.renewalJSON = renewalJSON; self.verified = verified
    }
}
public struct EntitlementEvidence: Sendable {
    public var current: [TransactionDetails]
    public var history: [TransactionDetails]
    public var subscriptions: [SubscriptionDetails]
    public var complete: Bool
    public var issues: [StoreFailure]
    public var rejectedKeys: Set<String> = []
    public init(current: [TransactionDetails] = [], history: [TransactionDetails] = [],
                subscriptions: [SubscriptionDetails] = [], complete: Bool = true, issues: [StoreFailure] = []) {
        self.current = current; self.history = history; self.subscriptions = subscriptions
        self.complete = complete; self.issues = issues
    }
}
public struct EntitlementGrant: Codable, Sendable, Equatable, Identifiable {
    public var id: String { transactionKey + "|" + entitlementID }
    public let entitlementID: String
    public let productID: String
    public let transactionKey: String
    public let validUntil: Date?
    public let ownership: Ownership
    public let reason: String
}
public struct ProStatus: Codable, Sendable, Equatable {
    public var access: Access
    public var sources: [EntitlementGrant]
    public var evaluatedAt: Date
    public var isStale: Bool
    public var reason: String
    public var validUntil: Date? {
        guard !sources.isEmpty, sources.allSatisfy({ $0.validUntil != nil }) else { return nil }
        return sources.compactMap(\.validUntil).max()
    }
}
public struct EntitlementSnapshot: Codable, Sendable, Equatable {
    public var grants: [EntitlementGrant] = []
    public var pro = ProStatus(access: .unknown, sources: [], evaluatedAt: .distantPast, isStale: false, reason: "尚未检查")
    public var nextEvaluationAt: Date?
    public init() {}
    init(grants: [EntitlementGrant], pro: ProStatus, nextEvaluationAt: Date?) {
        self.grants = grants; self.pro = pro; self.nextEvaluationAt = nextEvaluationAt
    }
    public func has(_ entitlement: String) -> Bool { grants.contains { $0.entitlementID == entitlement } }
}
public enum OfferSelection: Sendable, Equatable {
    case automatic, promotional(id: String), winBack(id: String)
}
public struct PurchaseRequest: Sendable {
    public let productID: String
    public let quantity: Int
    public let offer: OfferSelection
    public let appAccountToken: UUID?
    public let operationID: UUID
    public internal(set) var expectedKind: ProductKind?
    public init(productID: String, quantity: Int = 1, offer: OfferSelection = .automatic, appAccountToken: UUID? = nil) {
        self.productID = productID; self.quantity = quantity; self.offer = offer
        self.appAccountToken = appAccountToken; operationID = UUID()
        expectedKind = nil
    }
}
public enum PurchaseOutcome: Sendable, Equatable {
    case completed(TransactionDetails), pending(productID: String), userCancelled
    case processing(TransactionDetails, StoreFailure)
}
public enum GatewayPurchaseResult: Sendable { case transaction(TransactionDetails), pending, userCancelled }
public struct PurchaseIntentDetails: Sendable, Equatable {
    public let productID: String
    public let offer: OfferSelection
    public let offerDetails: OfferDetails?
    public init(productID: String, offer: OfferSelection = .automatic, offerDetails: OfferDetails? = nil) {
        self.productID = productID; self.offer = offer; self.offerDetails = offerDetails
    }
}
public enum GatewayUpdate: Sendable {
    case transaction(TransactionDetails), changed, storefrontChanged, failure(StoreFailure), purchaseIntent(PurchaseIntentDetails)
}
public struct StoreSnapshot: Sendable, Equatable {
    public enum Lifecycle: String, Sendable { case stopped, starting, ready }
    public var lifecycle: Lifecycle = .stopped
    public var revision: UInt64 = 0
    public var products: [ProductDetails] = []
    public var missingProductIDs: [String] = []
    public var catalogIsStale = false
    public var entitlements = EntitlementSnapshot()
    public var entitlementIssues: [StoreFailure] = []
    public var subscriptions: [SubscriptionDetails] = []
    public var pendingProductIDs: Set<String> = []
    public var activeOperation: UUID?
    public var balances: [String: Int] = [:]
    public var deliveries: [DeliveryRecord] = []
    public var lastFailure: StoreFailure?
    public var purchaseIntent: PurchaseIntentDetails?
    public var purchaseIntentProductID: String? { purchaseIntent?.productID }
    public init() {}
}
public struct StoreEvent: Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case started, stopped, productsUpdated, entitlementsChanged, proStatusChanged, subscriptionStatusChanged
        case purchaseStarted, purchaseCompleted, purchasePending, purchaseCancelled, purchaseFailed
        case deliveryDeferred, deliveryCompleted, transactionFinished, entitlementRevoked
        case restoreStarted, restoreCompleted, restoreFailed, storefrontChanged, purchaseIntent, error
        case refundRequestSubmitted, refundRequestCancelled, managementDismissed, offerCodeDismissed, eventGapDetected
    }
    public let id: UUID
    public let sequence: UInt64
    public let kind: Kind
    public let snapshotRevision: UInt64
    public let productID: String?
    public let transactionKey: String?
    public let operationID: UUID?
    public let failure: StoreFailure?
}
public struct RestoreReport: Sendable {
    public let entitlements: EntitlementSnapshot
    public let pendingDeliveries: Int
    public let issues: [StoreFailure]
}
/// Optional hooks. Default operation never calls a backend.
public protocol DeliveryHandler: Sendable {
    /// Implementations must deduplicate this key, including after a timeout.
    func deliver(_ transaction: TransactionDetails, idempotencyKey: String) async throws
    func revoke(_ transaction: TransactionDetails, idempotencyKey: String) async throws
}
public protocol TransactionValidator: Sendable {
    func validate(_ transaction: TransactionDetails) async throws
}
public protocol OfferSigner: Sendable {
    func signature(productID: String, offerID: String, appAccountToken: UUID?) async throws -> String
}
public protocol StoreGateway: Sendable {
    func products(for ids: [String]) async throws -> [ProductDetails]
    func evidence(groupIDs: Set<String>) async -> EntitlementEvidence
    func history() async throws -> [TransactionDetails]
    func unfinished() async throws -> [TransactionDetails]
    func purchase(_ request: PurchaseRequest) async throws -> GatewayPurchaseResult
    func finish(_ transaction: TransactionDetails) async
    func sync() async throws
    func updates() async -> AsyncStream<GatewayUpdate>
    func stop() async
}
