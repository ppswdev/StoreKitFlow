import Foundation
import Observation
import StoreKit
#if os(iOS)
import UIKit
#endif

/// Own one client at your App root. Its snapshots drive UI; event handlers must never perform delivery.
@MainActor @Observable
public final class StoreClient {
    public private(set) var snapshot = StoreSnapshot()
    public var products: [ProductDetails] { snapshot.products }
    public var proStatus: ProStatus { snapshot.entitlements.pro }
    public var isPro: Bool { proStatus.access == .active }
    @ObservationIgnored private let coordinator: StoreCoordinator
    @ObservationIgnored private let appleGateway: AppleStoreGateway?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var eventsSubscribers: [UUID: AsyncStream<StoreEvent>.Continuation] = [:]

    public init(configuration: StoreConfiguration, gateway: (any StoreGateway)? = nil,
                delivery: (any DeliveryHandler)? = nil, validator: (any TransactionValidator)? = nil,
                offerSigner: (any OfferSigner)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        let apple = (gateway as? AppleStoreGateway) ?? (gateway == nil ? AppleStoreGateway(offerSigner: offerSigner) : nil)
        appleGateway = apple
        coordinator = StoreCoordinator(configuration: configuration, gateway: gateway ?? apple!,
                                       delivery: delivery, validator: validator, now: now)
    }
    public func start() async throws {
        if observationTask == nil {
            let stream = await coordinator.observations()
            observationTask = Task { [weak self] in
                for await observation in stream {
                    guard !Task.isCancelled else { break }
                    self?.receive(observation)
                }
            }
        }
        do { try await coordinator.start(); await synchronize() }
        catch { await synchronize(); throw error }
    }
    public func stop() async {
        await coordinator.stop()
        await synchronize()
        observationTask?.cancel(); observationTask = nil
        eventsSubscribers.values.forEach { $0.finish() }; eventsSubscribers.removeAll()
    }
    deinit { observationTask?.cancel(); eventsSubscribers.values.forEach { $0.finish() } }
    private func receive(_ update: StoreObservation) {
        if update.snapshot.revision >= snapshot.revision { snapshot = update.snapshot }
        if let event = update.event {
            for continuation in eventsSubscribers.values { continuation.yield(event) }
        }
    }
    private func synchronize() async { snapshot = await coordinator.currentSnapshot() }
    /// Independent broadcast subscription. Compare sequence values to detect gaps and reread snapshot.
    public func events() -> AsyncStream<StoreEvent> {
        let id = UUID()
        let pair = AsyncStream<StoreEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        eventsSubscribers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.eventsSubscribers[id] = nil }
        }
        return pair.stream
    }
    @discardableResult public func refreshProducts() async throws -> [ProductDetails] {
        do { let result = try await coordinator.refreshProducts(); await synchronize(); return result }
        catch { await synchronize(); throw error }
    }
    public func productDetails(for id: String) async throws -> ProductDetails {
        if let product = products.first(where: { $0.id == id }), !snapshot.catalogIsStale { return product }
        let values = try await refreshProducts()
        guard let product = values.first(where: { $0.id == id }) else { throw StoreFailure(.productUnavailable, "商品不可用：\(id)") }
        return product
    }
    public func refreshEntitlements() async { await coordinator.refreshEntitlements(); await synchronize() }
    public func refreshOnForeground() async {
        await coordinator.recoverTransactions()
        await refreshEntitlements()
        if snapshot.catalogIsStale { _ = try? await refreshProducts() }
    }
    public func purchase(_ request: PurchaseRequest) async throws -> PurchaseOutcome {
        do { let result = try await coordinator.purchase(request); await synchronize(); return result }
        catch { await synchronize(); throw error }
    }
    public func purchase(productID: String) async throws -> PurchaseOutcome { try await purchase(.init(productID: productID)) }
    public func restorePurchases() async throws -> RestoreReport {
        do { let report = try await coordinator.restore(); await synchronize(); return report }
        catch { await synchronize(); throw error }
    }
    public func transactionHistory() async throws -> [TransactionDetails] { try await coordinator.history() }
    public func retryDelivery(for transactionKey: String) async throws {
        do { try await coordinator.retry(transactionKey); await synchronize() }
        catch { await synchronize(); throw error }
    }
    public func consume(balanceKey: String, amount: Int) async throws {
        try await coordinator.consume(balanceKey, amount: amount); await synchronize()
    }
    /// Forward success from native StoreKit views to the SAME transaction processor.
    public func processExternalPurchaseResult(_ result: Product.PurchaseResult, productID: String) async throws -> PurchaseOutcome {
        let gatewayResult: GatewayPurchaseResult
        switch result {
        case .success(let verification):
            guard case .verified(let native) = verification else { throw StoreFailure(.verificationFailed, "交易未验证") }
            var transaction = AppleStoreGateway.details(native)
            transaction.signedJWS = verification.jwsRepresentation
            if let appleGateway { transaction = try appleGateway.register(verification) }
            gatewayResult = .transaction(transaction)
        case .userCancelled: gatewayResult = .userCancelled
        case .pending: gatewayResult = .pending
        @unknown default: throw StoreFailure(.unsupportedCapability, "未知购买结果")
        }
        do {
            let outcome = try await coordinator.completePurchase(gatewayResult, request: .init(productID: productID))
            await synchronize(); return outcome
        } catch { await synchronize(); throw error }
    }
    public func storeKitProduct(for id: String) async throws -> Product {
        guard let appleGateway else { throw StoreFailure(.unsupportedCapability, "预览或自定义 Gateway 不提供原生商品") }
        return try await appleGateway.nativeProduct(for: id)
    }
    #if os(iOS)
    public func setPurchaseScene(_ scene: UIWindowScene?) { appleGateway?.purchaseScene = scene }

    public func manageSubscriptions(groupID: String? = nil, in scene: UIWindowScene) async throws {
        try ensureActive(scene)
        if let groupID { try await AppStore.showManageSubscriptions(in: scene, subscriptionGroupID: groupID) }
        else { try await AppStore.showManageSubscriptions(in: scene) }
        await coordinator.presentationEvent(.managementDismissed)
        await refreshEntitlements()
    }
    public enum RefundRequestOutcome: Sendable { case requestSubmitted, userCancelled }
    public func requestRefund(transactionID: String, in scene: UIWindowScene) async throws -> RefundRequestOutcome {
        try ensureActive(scene)
        guard let id = UInt64(transactionID) else { throw StoreFailure(.configuration, "无效交易 ID") }
        let result = try await StoreKit.Transaction.beginRefundRequest(for: id, in: scene)
        switch result {
        case .success: await coordinator.presentationEvent(.refundRequestSubmitted); return .requestSubmitted
        case .userCancelled: await coordinator.presentationEvent(.refundRequestCancelled); return .userCancelled
        @unknown default: throw StoreFailure(.unsupportedCapability, "未知退款请求结果")
        }
    }
    public func redeemOfferCode(in scene: UIWindowScene) async throws {
        try ensureActive(scene)
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
        await coordinator.presentationEvent(.offerCodeDismissed)
        await refreshEntitlements()
    }
    public func requestReview(in scene: UIWindowScene) { AppStore.requestReview(in: scene) }
    private func ensureActive(_ scene: UIWindowScene) throws {
        guard scene.activationState == .foregroundActive else { throw StoreFailure(.presentationUnavailable, "当前窗口未激活") }
    }
    #endif
}
