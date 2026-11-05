#if os(iOS)
import XCTest
import StoreKit
import StoreKitTest
import UIKit
@testable import StoreKitFlow

/// Hosted by StoreKitFlowExample. Run that scheme on an iOS simulator.
final class StoreKitIntegrationTests: XCTestCase {
    let coinID = "com.ppswdev.store.goldcoin.10"
    let lifetimeID = "com.ppswdev.store.lifetimevip"
    let monthlyID = "com.ppswdev.store.inapp.monthlyvip"
    let termID = "com.ppswdev.store.non.monthlyvip"

    @MainActor private func setupStore() async throws -> (SKTestSession, StoreClient) {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "StoreProducts", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState(); session.disableDialogs = true; session.timeRate = .realTime; session.clearTransactions()
        let configuration = StoreConfiguration(products: [
            .init(coinID, kind: .consumable, credits: 10),
            .init(lifetimeID, kind: .nonConsumable, entitlements: ["pro"]),
            .init(monthlyID, kind: .autoRenewable, entitlements: ["pro"]),
            .init(termID, kind: .nonRenewable, entitlements: ["pro"], term: Term(1, .month))
        ], storageURL: FileManager.default.temporaryDirectory.appending(path: "StoreKitFlowIntegration/\(UUID())/ledger.json"))
        let client = StoreClient(configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        client.setPurchaseScene(scene)
        try await client.start()
        return (session, client)
    }
    @MainActor private func buy(_ id: String, quantity: Int = 1, with client: StoreClient) async throws -> TransactionDetails {
        let result = try await client.purchase(.init(productID: id, quantity: quantity))
        guard case .completed(let transaction) = result else { throw StoreFailure(.system, "本地测试交易未完成交付：\(result)") }
        return transaction
    }
    @MainActor private func eventually(_ client: StoreClient, timeout: Double = 6, file: StaticString = #filePath, line: UInt = #line, _ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<Int(timeout / 0.2) {
            await client.refreshOnForeground()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        let states = client.snapshot.subscriptions.map { "\($0.state.rawValue), renew=\(String(describing: $0.willAutoRenew)), expires=\(String(describing: $0.transaction.expirationDate))" }
        XCTFail("StoreKit 状态在 \(timeout) 秒内未收敛：Pro=\(client.proStatus.access) 状态=\(states)", file: file, line: line)
    }
    @MainActor func testCatalogAndFourProductTypes() async throws {
        let (session, client) = try await setupStore()
        XCTAssertEqual(Set(client.products.map(\.kind)), [.consumable, .nonConsumable, .autoRenewable, .nonRenewable])
        XCTAssertTrue(client.snapshot.missingProductIDs.isEmpty)
        XCTAssertFalse(client.isPro)
        let coins = try await buy(coinID, quantity: 2, with: client)
        XCTAssertEqual(client.snapshot.balances[DeliveryLedger.balanceKey(coins)], 20)
        XCTAssertFalse(client.isPro)
        _ = try await buy(termID, with: client)
        XCTAssertTrue(client.isPro)
        _ = try await buy(lifetimeID, with: client)
        XCTAssertNil(client.proStatus.validUntil)
        _ = try await buy(monthlyID, with: client)
        XCTAssertTrue(client.proStatus.sources.contains { $0.productID == monthlyID })
        await client.stop(); session.clearTransactions()
    }
    @MainActor func testRefundRevokesOnlyItsSource() async throws {
        let (session, client) = try await setupStore()
        _ = try await buy(lifetimeID, with: client)
        let subscription = try await buy(monthlyID, with: client)
        try session.refundTransaction(identifier: try XCTUnwrap(UInt(subscription.id)))
        try await eventually(client) { !client.proStatus.sources.contains { $0.productID == self.monthlyID } }
        XCTAssertTrue(client.isPro)
        XCTAssertTrue(client.proStatus.sources.contains { $0.productID == lifetimeID })
        await client.stop(); session.clearTransactions()
    }
    @MainActor func testCancellingRenewalKeepsCurrentAccess() async throws {
        let (session, client) = try await setupStore()
        session.timeRate = .oneRenewalEveryTenSeconds
        let t = try await buy(monthlyID, with: client)
        try session.disableAutoRenewForTransaction(identifier: try XCTUnwrap(UInt(t.id)))
        try await eventually(client) { client.snapshot.subscriptions.contains { $0.willAutoRenew == false } }
        XCTAssertTrue(client.isPro)
        // Accelerated natural expiry exercises the same deadline path as production.
        try await eventually(client, timeout: 20) { client.proStatus.access == .inactive }
        await client.stop(); session.clearTransactions()
    }
    @MainActor func testRefundedConsumableCompensatesLocalBalance() async throws {
        let (session, client) = try await setupStore()
        let t = try await buy(coinID, with: client)
        try session.refundTransaction(identifier: try XCTUnwrap(UInt(t.id)))
        try await eventually(client) { client.snapshot.balances[DeliveryLedger.balanceKey(t)] == 0 }
        XCTAssertFalse(client.isPro)
        await client.stop(); session.clearTransactions()
    }
    @MainActor func testAskToBuyApprovalUsesUpdatePipeline() async throws {
        let (session, client) = try await setupStore()
        session.askToBuyEnabled = true
        let result = try await client.purchase(productID: monthlyID)
        XCTAssertEqual(result, .pending(productID: monthlyID))
        XCTAssertFalse(client.isPro)
        let pending = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == monthlyID })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await eventually(client) { client.isPro && !client.snapshot.pendingProductIDs.contains(self.monthlyID) }
        await client.stop(); session.clearTransactions()
    }
    @MainActor func testNativeStoreKitPurchaseCallbackUsesSameLedger() async throws {
        let (session, client) = try await setupStore()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let product = try await client.storeKitProduct(for: coinID)
        let nativeResult = try await product.purchase(confirmIn: scene)
        let outcome = try await client.processExternalPurchaseResult(nativeResult, productID: coinID)
        guard case .completed(let t) = outcome else { XCTFail("原生购买未完成"); return }
        _ = try await client.processExternalPurchaseResult(nativeResult, productID: coinID)
        XCTAssertEqual(client.snapshot.balances[DeliveryLedger.balanceKey(t)], 10)
        await client.stop(); session.clearTransactions()
    }
}
#endif
