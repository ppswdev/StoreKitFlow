import Foundation

/// An explicitly injected, offline adapter for previews and deterministic failure testing.
/// Never selected automatically in production.
public actor PreviewStoreGateway: StoreGateway {
    private var catalog: [ProductDetails]
    private var currentEvidence: EntitlementEvidence
    private var pending: [TransactionDetails] = []
    private var continuations: [UUID: AsyncStream<GatewayUpdate>.Continuation] = [:]
    private var nextResult: GatewayPurchaseResult = .userCancelled
    private var failure: StoreFailure?
    private var latency: Duration = .zero
    public private(set) var finishedKeys: [String] = []
    public private(set) var purchaseCount = 0
    public private(set) var syncCount = 0
    public private(set) var updatesCount = 0
    public private(set) var productRequestCount = 0
    public init(products: [ProductDetails] = [], evidence: EntitlementEvidence = .init()) {
        catalog = products; currentEvidence = evidence
    }
    public func setEvidence(_ value: EntitlementEvidence) { currentEvidence = value }
    public func setUnfinished(_ value: [TransactionDetails]) { pending = value }
    public func setPurchaseResult(_ value: GatewayPurchaseResult) { nextResult = value }
    public func setFailure(_ value: StoreFailure?) { failure = value }
    public func setLatency(_ value: Duration) { latency = value }
    public func emit(_ update: GatewayUpdate) { continuations.values.forEach { $0.yield(update) } }
    public func products(for ids: [String]) async throws -> [ProductDetails] {
        productRequestCount += 1
        try await Task.sleep(for: latency)
        if let failure { throw failure }
        return ids.compactMap { id in catalog.first { $0.id == id } }
    }
    public func evidence(groupIDs: Set<String>) async -> EntitlementEvidence {
        let result = currentEvidence
        try? await Task.sleep(for: latency)
        if let failure { return .init(complete: false, issues: [failure]) }
        return result
    }
    public func history() throws -> [TransactionDetails] { if let failure { throw failure }; return currentEvidence.history }
    public func unfinished() throws -> [TransactionDetails] { if let failure { throw failure }; return pending }
    public func purchase(_ request: PurchaseRequest) async throws -> GatewayPurchaseResult {
        try await Task.sleep(for: latency)
        if let failure { throw failure }
        purchaseCount += 1
        if case .transaction(let t) = nextResult {
            pending.append(t)
            currentEvidence.history.removeAll { $0.key == t.key }; currentEvidence.history.append(t)
            if t.kind != .consumable { currentEvidence.current.removeAll { $0.key == t.key }; currentEvidence.current.append(t) }
        }
        return nextResult
    }
    public func finish(_ transaction: TransactionDetails) { finishedKeys.append(transaction.key); pending.removeAll { $0.key == transaction.key } }
    public func sync() throws { syncCount += 1; if let failure { throw failure } }
    public func updates() -> AsyncStream<GatewayUpdate> {
        updatesCount += 1
        let id = UUID()
        let pair = AsyncStream<GatewayUpdate>.makeStream()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return pair.stream
    }
    private func remove(_ id: UUID) { continuations[id] = nil }
    public func stop() { continuations.values.forEach { $0.finish() }; continuations.removeAll() }
}

extension ProductDetails {
    public static func preview(id: String, kind: ProductKind, name: String, price: Decimal = 9.99) -> ProductDetails {
        ProductDetails(id: id, kind: kind, rawType: kind.rawValue, displayName: name, description: "离线预览商品",
            price: price, displayPrice: "¥\(price)", currencyCode: "CNY", familyShareable: false,
            groupID: nil, periodValue: nil, periodUnit: nil, offers: [], rawJSON: Data(), fetchedAt: .distantPast)
    }
}
