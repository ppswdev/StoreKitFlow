import Foundation
import Testing
@testable import StoreKitFlow

actor CountingDelivery: DeliveryHandler {
    var delivered: Set<String> = []
    var revoked: Set<String> = []
    var shouldFail = false
    var deliverCalls = 0
    func setFail(_ value: Bool) { shouldFail = value }
    func deliver(_ t: TransactionDetails, idempotencyKey: String) async throws {
        deliverCalls += 1
        try await Task.sleep(for: .milliseconds(5))
        if shouldFail { throw StoreFailure(.deliveryFailed, "测试交付暂时失败") }
        delivered.insert(idempotencyKey)
    }
    func revoke(_ t: TransactionDetails, idempotencyKey: String) { revoked.insert(idempotencyKey) }
}
func coordinator(_ config: StoreConfiguration, gateway: PreviewStoreGateway,
                 delivery: (any DeliveryHandler)? = nil) -> StoreCoordinator {
    StoreCoordinator(configuration: config, gateway: gateway, delivery: delivery, validator: nil, now: { evaluationDate })
}
@Test func concurrentDuplicateTransactionsDeliverOnce() async throws {
    let config = configuration(); let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    let core = coordinator(config, gateway: gateway, delivery: handler)
    try await core.start()
    let t = transaction("coins", kind: .consumable)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<20 { group.addTask { _ = await core.process(t) } }
    }
    #expect(await handler.delivered.count == 1)
    #expect(await handler.deliverCalls == 1)
    #expect(await core.currentSnapshot().balances[DeliveryLedger.balanceKey(t)] == 10)
    await core.stop()
}
@Test func refundArrivingDuringDeliveryIsNotDropped() async throws {
    let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    let core = coordinator(configuration(), gateway: gateway, delivery: handler)
    try await core.start()
    let t = transaction("coins", kind: .consumable)
    var revoked = t; revoked.revocationDate = evaluationDate; revoked.signedDate.addTimeInterval(1)
    async let first = core.process(t)
    try await Task.sleep(for: .milliseconds(1))
    async let second = core.process(revoked)
    _ = await (first, second)
    #expect(await core.currentSnapshot().balances[DeliveryLedger.balanceKey(t)] == 0)
    #expect(await handler.revoked.count == 1)
    await core.stop()
}
@Test func failedDeliveryDoesNotFinishOrGrantProAndCanRetry() async throws {
    let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    await handler.setFail(true)
    let core = coordinator(configuration(), gateway: gateway, delivery: handler)
    try await core.start()
    let t = transaction()
    await gateway.setPurchaseResult(.transaction(t))
    let outcome = try await core.purchase(.init(productID: "monthly"))
    guard case .processing = outcome else { Issue.record("应返回交付处理中"); return }
    #expect(await gateway.finishedKeys.isEmpty)
    #expect(await core.currentSnapshot().entitlements.pro.access != .active)
    await handler.setFail(false)
    try await core.retry(t.key)
    #expect(await core.currentSnapshot().entitlements.pro.access == .active)
    #expect(await gateway.finishedKeys.contains(t.key))
    await core.stop()
}
@Test func deliveredButUnfinishedRecordOnlyFinishesAfterRestart() async throws {
    let config = configuration(); let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    let t = transaction("coins", kind: .consumable)
    let ledger = DeliveryLedger(url: config.storageURL)
    _ = try await ledger.observe(t); try await ledger.markDelivered(t, credits: 10)
    await gateway.setUnfinished([t])
    let core = coordinator(config, gateway: gateway, delivery: handler)
    try await core.start()
    #expect(await handler.delivered.isEmpty)
    #expect(await gateway.finishedKeys.contains(t.key))
    #expect(await core.currentSnapshot().balances[DeliveryLedger.balanceKey(t)] == 10)
    await core.stop()
}
@Test func pendingPurchasePersistsWithoutGranting() async throws {
    let config = configuration(); let gateway = PreviewStoreGateway()
    await gateway.setPurchaseResult(.pending)
    let core = coordinator(config, gateway: gateway)
    try await core.start()
    #expect(try await core.purchase(.init(productID: "monthly")) == .pending(productID: "monthly"))
    #expect(await core.currentSnapshot().entitlements.pro.access == .inactive)
    await core.stop(); try await core.start()
    #expect(await core.currentSnapshot().pendingProductIDs.contains("monthly"))
    await core.stop()
}
@Test func purchaseCancellationDoesNotRevokeExistingPro() async throws {
    let gateway = PreviewStoreGateway(evidence: .init(current: [transaction()]))
    let core = coordinator(configuration(), gateway: gateway)
    try await core.start()
    #expect(try await core.purchase(.init(productID: "monthly")) == .userCancelled)
    #expect(await core.currentSnapshot().entitlements.pro.access == .active)
    await core.stop()
}
@Test func startupDoesNotSyncAndRestoreErrorsThrow() async throws {
    let gateway = PreviewStoreGateway(); let core = coordinator(configuration(), gateway: gateway)
    try await core.start(); try await core.start()
    #expect(await gateway.syncCount == 0)
    await gateway.setFailure(.init(.network, "离线"))
    await #expect(throws: StoreFailure.self) { try await core.restore() }
    #expect(await gateway.syncCount == 1)
    await core.stop()
}
@Test func emptyRestoreDoesNotClaimPro() async throws {
    let gateway = PreviewStoreGateway(); let core = coordinator(configuration(), gateway: gateway)
    try await core.start()
    let report = try await core.restore()
    #expect(report.entitlements.pro.access == .inactive)
    #expect(report.pendingDeliveries == 0)
    await core.stop()
}
@Test func catalogFailureDoesNotClearValidEntitlements() async throws {
    let gateway = PreviewStoreGateway(evidence: .init(current: [transaction()]))
    let core = coordinator(configuration(), gateway: gateway)
    try await core.start()
    await gateway.setFailure(.init(.network, "离线"))
    await #expect(throws: StoreFailure.self) { try await core.refreshProducts() }
    #expect(await core.currentSnapshot().entitlements.pro.access == .active)
    #expect(await core.currentSnapshot().catalogIsStale)
    await core.stop()
}
@Test func twoRenewalsWithSameOriginalIDAreNotDeduplicated() async throws {
    let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    let core = coordinator(configuration(), gateway: gateway, delivery: handler)
    try await core.start()
    var a = transaction(id: "1"); a.originalID = "original"
    var b = a; b.id = "2"
    _ = await core.process(a); _ = await core.process(b)
    #expect(await handler.delivered.count == 2)
    await core.stop()
}
@Test func missingProductsAreReportedWithoutInventedCause() async throws {
    let gateway = PreviewStoreGateway(products: [.preview(id: "lifetime", kind: .nonConsumable, name: "终身")])
    let core = coordinator(configuration(), gateway: gateway)
    try await core.start()
    #expect(await core.currentSnapshot().missingProductIDs.count == 3)
    #expect(await core.currentSnapshot().products.count == 1)
    await core.stop()
}
@Test func invalidQuantityNeverReachesPayment() async throws {
    let gateway = PreviewStoreGateway(); let core = coordinator(configuration(), gateway: gateway)
    try await core.start()
    await #expect(throws: StoreFailure.self) { try await core.purchase(.init(productID: "monthly", quantity: 2)) }
    #expect(await gateway.purchaseCount == 0)
    await core.stop()
}
@Test func operationRequiresStartup() async {
    let gateway = PreviewStoreGateway(); let core = coordinator(configuration(), gateway: gateway)
    await #expect(throws: StoreFailure.self) { try await core.purchase(.init(productID: "monthly")) }
    #expect(await gateway.purchaseCount == 0)
}
@Test func repeatedStopClearsRightsAndKeepsMonotonicRevisions() async throws {
    let gateway = PreviewStoreGateway(evidence: .init(current: [transaction()]))
    let core = coordinator(configuration(), gateway: gateway)
    try await core.start(); let old = await core.currentSnapshot().revision
    await core.stop(); await core.stop()
    #expect(await core.currentSnapshot().revision > old)
    #expect(await core.currentSnapshot().entitlements.pro.access == .unknown)
}

@Test func concurrentStartRegistersOneListenerAndOneCatalogRequest() async throws {
    let gateway = PreviewStoreGateway(); await gateway.setLatency(.milliseconds(10))
    let core = coordinator(configuration(), gateway: gateway)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<12 { group.addTask { try await core.start() } }
        try await group.waitForAll()
    }
    #expect(await gateway.updatesCount == 1)
    #expect(await gateway.productRequestCount == 1)
    await core.stop()
}
@Test func simultaneousPurchaseDoesNotSendTwoPaymentRequests() async throws {
    let gateway = PreviewStoreGateway(); let core = coordinator(configuration(), gateway: gateway)
    try await core.start(); await gateway.setLatency(.milliseconds(30))
    async let first = core.purchase(.init(productID: "monthly"))
    try await Task.sleep(for: .milliseconds(5))
    await #expect(throws: StoreFailure.self) { try await core.purchase(.init(productID: "monthly")) }
    _ = try await first
    #expect(await gateway.purchaseCount == 1)
    await core.stop()
}
@Test func stoppedSessionIgnoresDelayedEntitlementResponse() async throws {
    let gateway = PreviewStoreGateway(evidence: .init(current: [transaction()]))
    let core = coordinator(configuration(), gateway: gateway)
    try await core.start(); await gateway.setLatency(.milliseconds(30))
    async let refresh: Void = core.refreshEntitlements()
    try await Task.sleep(for: .milliseconds(5)); await core.stop()
    await refresh
    #expect(await core.currentSnapshot().lifecycle == .stopped)
    #expect(await core.currentSnapshot().entitlements.pro.access == .unknown)
}
@Test func restoredEntitlementWaitsForBusinessDeliveryConfirmation() async throws {
    let gateway = PreviewStoreGateway(evidence: .init(current: [transaction()]))
    let handler = CountingDelivery(); await handler.setFail(true)
    let core = coordinator(configuration(), gateway: gateway, delivery: handler)
    try await core.start()
    #expect(await core.currentSnapshot().entitlements.pro.access != .active)
    #expect(await gateway.finishedKeys.isEmpty)
    await core.stop()
}
@Test @MainActor func independentEventSubscribersSeeSameCompletedPurchase() async throws {
    let gateway = PreviewStoreGateway()
    let client = StoreClient(configuration: configuration(), gateway: gateway, now: { evaluationDate })
    try await client.start()
    let stream1 = client.events(); let stream2 = client.events()
    func completion(_ stream: AsyncStream<StoreEvent>) async -> StoreEvent? {
        for await event in stream { if event.kind == .purchaseCompleted { return event } }
        return nil
    }
    let first = Task { await completion(stream1) }; let second = Task { await completion(stream2) }
    await gateway.setPurchaseResult(.transaction(transaction()))
    _ = try await client.purchase(productID: "monthly")
    let a = await first.value; let b = await second.value
    #expect(a?.id == b?.id)
    #expect(a != nil)
    #expect(client.isPro)
    #expect(client.snapshot.revision >= (a?.snapshotRevision ?? 0))
    await client.stop()
}

@Test func resigningSameRefundDoesNotCompensateTwice() async throws {
    let gateway = PreviewStoreGateway(); let handler = CountingDelivery()
    let core = coordinator(configuration(), gateway: gateway, delivery: handler)
    try await core.start()
    var t = transaction("coins", kind: .consumable)
    _ = await core.process(t)
    t.revocationDate = evaluationDate; t.signedDate.addTimeInterval(1)
    _ = await core.process(t)
    t.signedDate.addTimeInterval(100)
    _ = await core.process(t)
    #expect(await handler.revoked.count == 1)
    #expect(await core.currentSnapshot().balances[DeliveryLedger.balanceKey(t)] == 0)
    await core.stop()
}
