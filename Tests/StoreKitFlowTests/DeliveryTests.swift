import Foundation
import Testing
@testable import StoreKitFlow

@Test func atomicDeliverySurvivesReloadAndDuplicate() async throws {
    let config = configuration()
    let ledger = DeliveryLedger(url: config.storageURL)
    let t = transaction("coins", kind: .consumable)
    _ = try await ledger.observe(t)
    try await ledger.markDelivered(t, credits: 10)
    let reopened = DeliveryLedger(url: config.storageURL)
    _ = try await reopened.observe(t)
    try await reopened.markDelivered(t, credits: 10)
    #expect(try await reopened.balances()[DeliveryLedger.balanceKey(t)] == 10)
}
@Test func refundsDeduplicateAndRecordSpentShortfall() async throws {
    let ledger = DeliveryLedger(url: configuration().storageURL)
    var t = transaction("coins", kind: .consumable)
    _ = try await ledger.observe(t); try await ledger.markDelivered(t, credits: 10)
    try await ledger.consume(balanceKey: DeliveryLedger.balanceKey(t), amount: 7)
    t.revocationDate = evaluationDate
    _ = try await ledger.observe(t); try await ledger.markRevoked(t); try await ledger.markRevoked(t)
    let record = try await ledger.record(for: t.key)
    #expect(record?.refundShortfall == 7)
    #expect(try await ledger.balances()[DeliveryLedger.balanceKey(t)] == 0)
}
@Test func partialRefundThenFullRefund() async throws {
    let ledger = DeliveryLedger(url: configuration().storageURL)
    var t = transaction("coins", kind: .consumable)
    _ = try await ledger.observe(t); try await ledger.markDelivered(t, credits: 10)
    t.revocationDate = evaluationDate; t.revocationPercentage = 50
    _ = try await ledger.observe(t); try await ledger.markRevoked(t)
    #expect(try await ledger.balances()[DeliveryLedger.balanceKey(t)] == 5)
    t.revocationPercentage = 100; t.signedDate.addTimeInterval(1)
    _ = try await ledger.observe(t); try await ledger.markRevoked(t)
    #expect(try await ledger.balances()[DeliveryLedger.balanceKey(t)] == 0)
}
@Test func corruptLedgerIsNeverSilentlyReset() async throws {
    let config = configuration()
    try FileManager.default.createDirectory(at: config.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("corrupt".utf8).write(to: config.storageURL)
    let ledger = DeliveryLedger(url: config.storageURL)
    await #expect(throws: StoreFailure.self) { try await ledger.records() }
    #expect(try String(contentsOf: config.storageURL, encoding: .utf8) == "corrupt")
}
@Test func balanceScopeSeparatesEnvironments() async throws {
    let ledger = DeliveryLedger(url: configuration().storageURL)
    let a = transaction("coins", kind: .consumable, id: "same")
    var b = a; b.environment = "production"
    for t in [a,b] { _ = try await ledger.observe(t); try await ledger.markDelivered(t, credits: 10) }
    #expect(try await ledger.balances().count == 2)
}
@Test func excessiveConsumptionDoesNotMutateBalance() async throws {
    let ledger = DeliveryLedger(url: configuration().storageURL)
    let t = transaction("coins", kind: .consumable)
    _ = try await ledger.observe(t); try await ledger.markDelivered(t, credits: 10)
    await #expect(throws: StoreFailure.self) { try await ledger.consume(balanceKey: DeliveryLedger.balanceKey(t), amount: 11) }
    #expect(try await ledger.balances()[DeliveryLedger.balanceKey(t)] == 10)
}
