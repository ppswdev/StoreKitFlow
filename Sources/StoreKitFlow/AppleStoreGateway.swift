import Foundation
import StoreKit
#if os(iOS)
import UIKit
#endif

/// Native StoreKit adapter. It performs local StoreKit verification; no application backend is required.
@MainActor
public final class AppleStoreGateway: StoreGateway {
    private var nativeProducts: [String: Product] = [:]
    private var nativeTransactions: [String: StoreKit.Transaction] = [:]
    private var tasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<GatewayUpdate>.Continuation?
    private let offerSigner: (any OfferSigner)?
    #if os(iOS)
    /// Set this to the presenting view's windowScene before purchase. Never choose an arbitrary connected scene.
    public weak var purchaseScene: UIWindowScene?
    #endif
    public init(offerSigner: (any OfferSigner)? = nil) { self.offerSigner = offerSigner }

    public func products(for ids: [String]) async throws -> [ProductDetails] {
        let products = try await Product.products(for: ids)
        var details: [ProductDetails] = []
        for product in products {
            nativeProducts[product.id] = product
            details.append(await Self.details(product))
        }
        let byID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func evidence(groupIDs: Set<String>) async -> EntitlementEvidence {
        var evidence = EntitlementEvidence()
        for await result in StoreKit.Transaction.currentEntitlements {
            if Task.isCancelled { evidence.complete = false; break }
            do { evidence.current.append(try verified(result)) }
            catch { evidence.complete = false; evidence.issues.append(.wrap(error)) }
        }
        do { evidence.history = try await history() }
        catch { evidence.complete = false; evidence.issues.append(.wrap(error)) }
        var groups = groupIDs
        groups.formUnion(nativeProducts.values.compactMap { $0.subscription?.subscriptionGroupID })
        // Current entitlements contain the group even if the product request failed.
        for transaction in nativeTransactions.values {
            if let id = transaction.subscriptionGroupID { groups.insert(id) }
        }
        for group in groups.sorted() {
            do {
                for status in try await Product.SubscriptionInfo.status(for: group) {
                    let transaction = try verified(status.transaction)
                    let renewal = try status.renewalInfo.payloadValue
                    evidence.subscriptions.append(SubscriptionDetails(groupID: group, state: Self.state(status.state),
                        transaction: transaction, willAutoRenew: renewal.willAutoRenew,
                        autoRenewPreference: renewal.autoRenewPreference,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        renewalDate: renewal.renewalDate, expirationReason: renewal.expirationReason.map { String(describing: $0) },
                        priceIncreaseStatus: String(describing: renewal.priceIncreaseStatus),
                        renewalJSON: renewal.jsonRepresentation, verified: true))
                }
            } catch { evidence.complete = false; evidence.issues.append(.wrap(error)) }
        }
        if Task.isCancelled { evidence.complete = false }
        return evidence
    }
    public func history() async throws -> [TransactionDetails] {
        var result: [TransactionDetails] = []
        for await value in StoreKit.Transaction.all {
            try Task.checkCancellation()
            result.append(try verified(value))
        }
        return result.sorted { $0.purchaseDate > $1.purchaseDate }
    }
    public func unfinished() async throws -> [TransactionDetails] {
        var result: [TransactionDetails] = []
        for await value in StoreKit.Transaction.unfinished {
            try Task.checkCancellation()
            do { result.append(try verified(value)) }
            catch { continuation?.yield(.failure(.wrap(error))) }
        }
        return result
    }
    public func purchase(_ request: PurchaseRequest) async throws -> GatewayPurchaseResult {
        guard AppStore.canMakePayments else { throw StoreFailure(.paymentsNotAllowed, "此设备不允许购买") }
        // Refresh the Product before purchase so a storefront change cannot silently reuse stale pricing.
        guard let product = try await Product.products(for: [request.productID]).first else {
            throw StoreFailure(.productUnavailable, "商品当前不可用")
        }
        nativeProducts[product.id] = product
        if let expected = request.expectedKind, expected != Self.kind(product.type) {
            throw StoreFailure(.configuration, "商品类型与配置不同，已阻止发起支付")
        }
        var options: Set<Product.PurchaseOption> = []
        if let token = request.appAccountToken { options.insert(.appAccountToken(token)) }
        if request.quantity != 1 { options.insert(.quantity(request.quantity)) }
        switch request.offer {
        case .automatic: break
        case .promotional(let id):
            guard product.subscription?.promotionalOffers.contains(where: { $0.id == id }) == true,
                  let offerSigner else { throw StoreFailure(.offerInvalid, "此促销需要可用优惠和签名服务") }
            let signature = try await offerSigner.signature(productID: product.id, offerID: id, appAccountToken: request.appAccountToken)
            guard !signature.isEmpty else { throw StoreFailure(.offerInvalid, "促销签名为空") }
            options.formUnion(Product.PurchaseOption.promotionalOffer(id, compactJWS: signature))
        case .winBack(let id):
            if #available(iOS 18, macOS 15, *), let subscription = product.subscription,
               let offer = subscription.winBackOffers.first(where: { $0.id == id }) {
                let statuses = try await subscription.status
                let eligible = statuses.contains { status in
                    guard let info = try? status.renewalInfo.payloadValue else { return false }
                    return info.eligibleWinBackOfferIDs.contains(id)
                }
                guard eligible else { throw StoreFailure(.offerInvalid, "当前账户不符合此召回优惠资格") }
                options.insert(.winBackOffer(offer))
            } else { throw StoreFailure(.unsupportedCapability, "当前系统或商品不支持此召回优惠") }
        }
        let result: Product.PurchaseResult
        #if os(iOS)
        guard let scene = purchaseScene, scene.activationState == .foregroundActive else {
            throw StoreFailure(.presentationUnavailable, "请从当前活跃窗口发起购买")
        }
        result = try await product.purchase(confirmIn: scene, options: options)
        #else
        result = try await product.purchase(options: options)
        #endif
        switch result {
        case .success(let verification): return .transaction(try verified(verification))
        case .pending: return .pending
        case .userCancelled: return .userCancelled
        @unknown default: throw StoreFailure(.unsupportedCapability, "未知购买结果，请刷新订单状态")
        }
    }
    public func finish(_ transaction: TransactionDetails) async {
        if let native = nativeTransactions[transaction.key] { await native.finish(); return }
        for await result in StoreKit.Transaction.unfinished {
            if let t = try? verified(result), t.key == transaction.key {
                await nativeTransactions[t.key]?.finish(); return
            }
        }
    }
    public func sync() async throws { try await AppStore.sync() }

    public func updates() async -> AsyncStream<GatewayUpdate> {
        stopTasks()
        let pair = AsyncStream<GatewayUpdate>.makeStream()
        continuation = pair.continuation
        tasks.append(Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { break }
                do { if let transaction = try self?.verified(result) { self?.continuation?.yield(.transaction(transaction)) } }
                catch { self?.continuation?.yield(.failure(.wrap(error))) }
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                guard !Task.isCancelled else { break }
                self?.continuation?.yield(.changed)
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in Storefront.updates {
                guard !Task.isCancelled else { break }
                self?.nativeProducts.removeAll()
                self?.continuation?.yield(.storefrontChanged)
            }
        })
        if #available(iOS 16.4, macOS 14.4, *) {
            tasks.append(Task { [weak self] in
                for await intent in PurchaseIntent.intents {
                    guard !Task.isCancelled else { break }
                    self?.nativeProducts[intent.product.id] = intent.product
                    var selection: OfferSelection = .automatic
                    var details: OfferDetails?
                    if #available(iOS 18, macOS 15, *), let offer = intent.offer {
                        if offer.type == .winBack, let id = offer.id {
                            selection = .winBack(id: id)
                            details = Self.offer(offer, type: "winBack", eligibility: .eligible)
                        } else if offer.type == .promotional, let id = offer.id {
                            selection = .promotional(id: id)
                            details = Self.offer(offer, type: "promotional", eligibility: .requiresSignature)
                        } else if offer.type == .introductory {
                            details = Self.offer(offer, type: "introductory", eligibility: .unknown)
                        } else {
                            self?.continuation?.yield(.failure(.init(.unsupportedCapability, "购买意向包含未知优惠，不能自动按原价购买")))
                            continue
                        }
                    }
                    self?.continuation?.yield(.purchaseIntent(.init(productID: intent.product.id, offer: selection, offerDetails: details)))
                }
            })
        }
        return pair.stream
    }
    private func stopTasks() {
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        continuation?.finish(); continuation = nil
    }
    public func stop() async { stopTasks() }
    deinit { tasks.forEach { $0.cancel() }; continuation?.finish() }

    /// Escape hatch for new SDK fields and Apple's native SwiftUI StoreKit views.
    public func nativeProduct(for id: String) async throws -> Product {
        guard let product = try await Product.products(for: [id]).first else {
            throw StoreFailure(.productUnavailable, "商品当前不可用")
        }
        nativeProducts[id] = product
        return product
    }

    func register(_ verification: VerificationResult<StoreKit.Transaction>) throws -> TransactionDetails { try verified(verification) }

    private func verified(_ result: VerificationResult<StoreKit.Transaction>) throws -> TransactionDetails {
        guard case .verified(let transaction) = result else { throw StoreFailure(.verificationFailed, "交易未通过 StoreKit 验证") }
        var dto = Self.details(transaction)
        dto.signedJWS = result.jwsRepresentation
        nativeTransactions[dto.key] = transaction
        return dto
    }
    static func kind(_ kind: Product.ProductType) -> ProductKind {
        switch kind {
        case .consumable: .consumable
        case .nonConsumable: .nonConsumable
        case .autoRenewable: .autoRenewable
        case .nonRenewable: .nonRenewable
        default: .unsupported
        }
    }
    static func state(_ state: Product.SubscriptionInfo.RenewalState) -> SubscriptionState {
        switch state {
        case .subscribed: .subscribed
        case .expired: .expired
        case .inGracePeriod: .inGracePeriod
        case .inBillingRetryPeriod: .inBillingRetryPeriod
        case .revoked: .revoked
        default: .unknown
        }
    }
    static func details(_ t: StoreKit.Transaction) -> TransactionDetails {
        var dto = TransactionDetails(id: String(t.id), originalID: String(t.originalID), productID: t.productID,
            kind: kind(t.productType), bundleID: t.appBundleID, environment: String(describing: t.environment),
            purchaseDate: t.purchaseDate, expirationDate: t.expirationDate, revocationDate: t.revocationDate,
            signedDate: t.signedDate, quantity: t.purchasedQuantity,
            ownership: t.ownershipType == .purchased ? .purchased : (t.ownershipType == .familyShared ? .familyShared : .unknown),
            isUpgraded: t.isUpgraded, appAccountToken: t.appAccountToken, rawJSON: t.jsonRepresentation)
        if #available(iOS 17.2, macOS 14.2, *), let offer = t.offer {
            dto.offerType = String(describing: offer.type)
            dto.offerPaymentMode = offer.paymentMode?.rawValue
        }
        if #available(iOS 26.4, macOS 26.4, *) {
            dto.revocationType = t.revocationType?.rawValue
            dto.revocationPercentage = t.revocationPercentage
        }
        return dto
    }
    static func details(_ p: Product) async -> ProductDetails {
        var offers: [OfferDetails] = []
        if let sub = p.subscription {
            if let intro = sub.introductoryOffer {
                offers.append(offer(intro, type: "introductory", eligibility: await sub.isEligibleForIntroOffer ? .eligible : .ineligible))
            }
            offers += sub.promotionalOffers.map { offer($0, type: "promotional", eligibility: .requiresSignature) }
            if #available(iOS 18, macOS 15, *) {
                var eligible: Set<String> = []
                var checked = false
                if let statuses = try? await sub.status {
                    checked = true
                    for status in statuses {
                        if let info = try? status.renewalInfo.payloadValue { eligible.formUnion(info.eligibleWinBackOfferIDs) }
                        else { checked = false }
                    }
                }
                offers += sub.winBackOffers.map { offer($0, type: "winBack", eligibility: checked ? (eligible.contains($0.id ?? "") ? .eligible : .ineligible) : .unknown) }
            }
        }
        return ProductDetails(id: p.id, kind: kind(p.type), rawType: p.type.rawValue, displayName: p.displayName,
            description: p.description, price: p.price, displayPrice: p.displayPrice,
            currencyCode: p.priceFormatStyle.currencyCode, familyShareable: p.isFamilyShareable,
            groupID: p.subscription?.subscriptionGroupID, periodValue: p.subscription?.subscriptionPeriod.value,
            periodUnit: p.subscription.map { String(describing: $0.subscriptionPeriod.unit) },
            offers: offers, rawJSON: p.jsonRepresentation, fetchedAt: Date())
    }
    static func offer(_ o: Product.SubscriptionOffer, type: String, eligibility: OfferDetails.Eligibility) -> OfferDetails {
        let mode: String = switch o.paymentMode { case .freeTrial: "freeTrial"; case .payAsYouGo: "payAsYouGo"; case .payUpFront: "payUpFront"; default: "unknown" }
        return OfferDetails(id: o.id ?? "introductory", type: type, price: o.price, displayPrice: o.displayPrice,
            periodValue: o.period.value, periodUnit: String(describing: o.period.unit), periodCount: o.periodCount,
            paymentMode: mode, eligibility: eligibility)
    }
}
