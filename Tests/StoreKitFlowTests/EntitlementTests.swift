import Foundation
import Testing
@testable import StoreKitFlow

let evaluationDate = Date(timeIntervalSince1970: 1_800_000_000)
func configuration(_ products: [ProductDefinition] = [
    .init("lifetime", kind: .nonConsumable, entitlements: ["pro"]),
    .init("monthly", kind: .autoRenewable, entitlements: ["pro"], groupID: "group"),
    .init("term", kind: .nonRenewable, entitlements: ["pro"], term: Term(1, .month)),
    .init("coins", kind: .consumable, credits: 10)
]) -> StoreConfiguration {
    StoreConfiguration(products: products,
        storageURL: FileManager.default.temporaryDirectory.appending(path: "StoreKitFlowTests/\(UUID())/ledger.json"), retryInterval: 3600)
}
func transaction(_ product: String = "monthly", kind: ProductKind = .autoRenewable, id: String = UUID().uuidString,
                 expiry: Date? = evaluationDate.addingTimeInterval(3600), revoked: Bool = false,
                 ownership: Ownership = .purchased, upgraded: Bool = false) -> TransactionDetails {
    TransactionDetails(id: id, productID: product, kind: kind, purchaseDate: evaluationDate.addingTimeInterval(-3600),
        expirationDate: expiry, revocationDate: revoked ? evaluationDate : nil, signedDate: evaluationDate,
        ownership: ownership, isUpgraded: upgraded)
}
func subscription(_ t: TransactionDetails, _ state: SubscriptionState, grace: Date? = nil, renews: Bool = true) -> SubscriptionDetails {
    SubscriptionDetails(groupID: "group", state: state, transaction: t, willAutoRenew: renews,
        autoRenewPreference: nil, gracePeriodExpirationDate: grace, renewalDate: nil,
        expirationReason: nil, priceIncreaseStatus: nil, renewalJSON: Data(), verified: true)
}

@Test(arguments: [SubscriptionState.subscribed, .inGracePeriod, .expired, .inBillingRetryPeriod, .revoked, .unknown])
func subscriptionStates(_ state: SubscriptionState) {
    let t = transaction(expiry: state == .inGracePeriod ? evaluationDate.addingTimeInterval(-1) : evaluationDate.addingTimeInterval(3600))
    let evidence = EntitlementEvidence(current: [t], subscriptions: [subscription(t, state, grace: evaluationDate.addingTimeInterval(500))])
    let pro = EntitlementResolver.resolve(evidence, configuration: configuration(), now: evaluationDate).pro
    let expected: Access = state == .unknown ? .unknown : ([SubscriptionState.subscribed, .inGracePeriod].contains(state) ? .active : .inactive)
    #expect(pro.access == expected)
}
@Test(arguments: [true, false]) func autoRenewPreferenceDoesNotRevoke(_ renews: Bool) {
    let t = transaction()
    let result = EntitlementResolver.resolve(.init(current: [t], subscriptions: [subscription(t, .subscribed, renews: renews)]), configuration: configuration(), now: evaluationDate)
    #expect(result.pro.access == .active)
}
@Test func lifetimeSurvivesSubscriptionRefund() {
    let lifetime = transaction("lifetime", kind: .nonConsumable, expiry: nil)
    let refunded = transaction(revoked: true)
    let result = EntitlementResolver.resolve(.init(current: [lifetime], history: [refunded], subscriptions: [subscription(refunded, .revoked)]), configuration: configuration(), now: evaluationDate)
    #expect(result.pro.access == .active)
    #expect(result.pro.sources.map(\.productID) == ["lifetime"])
}
@Test func completeEmptyClearsButIncompletePreservesBoundedAccess() {
    let t = transaction()
    let old = EntitlementResolver.resolve(.init(current: [t]), configuration: configuration(), now: evaluationDate)
    #expect(EntitlementResolver.resolve(.init(), configuration: configuration(), now: evaluationDate, previous: old).pro.access == .inactive)
    #expect(EntitlementResolver.resolve(.init(complete: false), configuration: configuration(), now: evaluationDate, previous: old).pro.access == .active)
    #expect(EntitlementResolver.resolve(.init(complete: false), configuration: configuration(), now: evaluationDate.addingTimeInterval(4000), previous: old).pro.access == .unknown)
}
@Test(arguments: [Ownership.purchased, .familyShared, .unknown]) func ownershipRules(_ ownership: Ownership) {
    let t = transaction(ownership: ownership)
    let result = EntitlementResolver.resolve(.init(current: [t]), configuration: configuration(), now: evaluationDate)
    #expect(result.pro.access == (ownership == .unknown ? .inactive : .active))
}
@Test func familySharingCanBeDisabled() {
    let t = transaction(ownership: .familyShared)
    let config = StoreConfiguration(products: configuration().products, acceptsFamilySharing: false)
    #expect(EntitlementResolver.resolve(.init(current: [t]), configuration: config, now: evaluationDate).pro.access == .inactive)
}
@Test func upgradedTransactionDoesNotGrant() {
    #expect(EntitlementResolver.resolve(.init(current: [transaction(upgraded: true)]), configuration: configuration(), now: evaluationDate).pro.access == .inactive)
}
@Test func historicalSubscriptionDoesNotGrantAndConsumablesNeverGrant() {
    let result = EntitlementResolver.resolve(.init(current: [transaction("coins", kind: .consumable)], history: [transaction()]), configuration: configuration(), now: evaluationDate)
    #expect(result.pro.access == .inactive)
}
@Test func futureExpiryInRevokedStateDoesNotGrant() {
    let t = transaction()
    #expect(EntitlementResolver.resolve(.init(current: [t], subscriptions: [subscription(t, .revoked)]), configuration: configuration(), now: evaluationDate).pro.access == .inactive)
}
@Test func missingGraceDeadlineIsUnknown() {
    let t = transaction(expiry: evaluationDate.addingTimeInterval(-1))
    #expect(EntitlementResolver.resolve(.init(current: [t], subscriptions: [subscription(t, .inGracePeriod)]), configuration: configuration(), now: evaluationDate).pro.access == .unknown)
}
@Test func newerRevocationWinsOverOldSnapshot() {
    var old = transaction()
    old.signedDate = evaluationDate.addingTimeInterval(-10)
    var revoked = old; revoked.signedDate = evaluationDate; revoked.revocationDate = evaluationDate
    let result = EntitlementResolver.resolve(.init(current: [old], history: [revoked], subscriptions: [subscription(old, .subscribed)]), configuration: configuration(), now: evaluationDate)
    #expect(result.pro.access == .inactive)
}
@Test func nonRenewingExpiresAndDoesNotUseAppleExpiry() {
    var t = transaction("term", kind: .nonRenewable, expiry: nil)
    t.purchaseDate = evaluationDate.addingTimeInterval(-40 * 86400)
    #expect(EntitlementResolver.resolve(.init(current: [t]), configuration: configuration(), now: evaluationDate).pro.access == .inactive)
    t.purchaseDate = evaluationDate
    #expect(EntitlementResolver.resolve(.init(history: [t]), configuration: configuration(), now: evaluationDate).pro.access == .active)
}
@Test func stackedTermsDeduplicateAndRecomputeAfterRefund() {
    let config = configuration([.init("term", kind: .nonRenewable, entitlements: ["pro"], term: Term(1, .day), stacks: true)])
    var first = transaction("term", kind: .nonRenewable, id: "1", expiry: nil)
    first.purchaseDate = evaluationDate.addingTimeInterval(-1.5 * 86400)
    var second = first; second.id = "2"; second.purchaseDate.addTimeInterval(100)
    let result = EntitlementResolver.resolve(.init(history: [first, first, second]), configuration: config, now: evaluationDate)
    #expect(result.pro.access == .active)
    first.revocationDate = evaluationDate
    #expect(EntitlementResolver.resolve(.init(history: [first, second]), configuration: config, now: evaluationDate).pro.access == .inactive)
}
@Test func calendarMonthIsNotThirtyDays() {
    let date = ISO8601DateFormatter().date(from: "2024-02-01T00:00:00Z")!
    let end = try! #require(Term(1, .month).end(from: date))
    #expect(end.timeIntervalSince(date) == TimeInterval(29 * 86400))
}

@Test func renewalStateIsNotOverruledByResignedTransaction() {
    let old = transaction()
    var resigned = old; resigned.signedDate.addTimeInterval(20)
    let evidence = EntitlementEvidence(current: [resigned], subscriptions: [subscription(old, .expired)])
    let value = EntitlementResolver.resolve(evidence, configuration: configuration(), now: evaluationDate)
    #expect(value.pro.access == .inactive)
}
