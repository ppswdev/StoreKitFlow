import Foundation

public struct DeliveryRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { transaction.key }
    public var transaction: TransactionDetails
    public var delivered = false
    public var finished = false
    public var revoked = false
    public var revocationProcessedAt: Date?
    public var revocationRevision: String?
    public var credited = 0
    public var refundedCredits = 0
    public var refundShortfall = 0
    public var attempts = 0
    public var nextRetryAt: Date?
    public var lastFailure: StoreFailure?
}

/// A single atomic document stores both the balance and the delivery marker.
/// Mutations are copy-on-write: in-memory state is committed only after the file write succeeds.
public actor DeliveryLedger {
    struct Document: Codable, Sendable {
        var version = 1
        var records: [String: DeliveryRecord] = [:]
        var balances: [String: Int] = [:]
        var pendingProducts: Set<String> = []
    }
    private let url: URL
    private var document: Document?
    public init(url: URL) { self.url = url }
    private func loaded() throws -> Document {
        if let document { return document }
        do {
            let value: Document
            if FileManager.default.fileExists(atPath: url.path) {
                value = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
                guard value.version == 1 else { throw StoreFailure(.persistenceFailed, "账本版本不受支持，不能清空重建") }
            } else { value = Document() }
            document = value
            return value
        } catch { throw StoreFailure(.persistenceFailed, "读取账本失败：\(error.localizedDescription)") }
    }
    private func commit(_ value: Document) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            document = value
        } catch { throw StoreFailure(.persistenceFailed, "保存账本失败：\(error.localizedDescription)") }
    }
    public func records() throws -> [DeliveryRecord] {
        try loaded().records.values.sorted { $0.transaction.purchaseDate > $1.transaction.purchaseDate }
    }
    public func record(for key: String) throws -> DeliveryRecord? { try loaded().records[key] }
    public func balances() throws -> [String: Int] { try loaded().balances }
    public func pendingProducts() throws -> Set<String> { try loaded().pendingProducts }
    public func setPending(_ id: String, pending: Bool) throws {
        var value = try loaded()
        if pending { value.pendingProducts.insert(id) } else { value.pendingProducts.remove(id) }
        try commit(value)
    }
    public func observe(_ transaction: TransactionDetails) throws -> DeliveryRecord {
        var value = try loaded()
        var record = value.records[transaction.key] ?? DeliveryRecord(transaction: transaction)
        if record.transaction.signedDate <= transaction.signedDate {
            // Never replace a known revocation with an older/plain purchase replay.
            if record.transaction.revocationDate == nil || transaction.revocationDate != nil {
                record.transaction = transaction
                if transaction.revocationDate != nil, record.revocationRevision != transaction.revocationKey {
                    record.finished = false
                }
            }
        }
        record.attempts += 1
        value.records[transaction.key] = record
        try commit(value)
        return record
    }
    public func markDelivered(_ t: TransactionDetails, credits: Int) throws {
        var value = try loaded()
        guard var record = value.records[t.key] else { throw StoreFailure(.persistenceFailed, "交付记录不存在") }
        guard !record.delivered, !record.revoked else { return }
        if t.kind == .consumable {
            let (amount, overflow) = credits.multipliedReportingOverflow(by: t.quantity)
            let key = Self.balanceKey(t)
            let (balance, balanceOverflow) = (value.balances[key] ?? 0).addingReportingOverflow(amount)
            guard amount > 0, !overflow, !balanceOverflow else { throw StoreFailure(.configuration, "消耗品数量超出范围") }
            value.balances[key] = balance
            record.credited = amount
        }
        record.delivered = true; record.lastFailure = nil; record.nextRetryAt = nil
        value.records[t.key] = record
        value.pendingProducts.remove(t.productID)
        try commit(value)
    }
    public func markRevoked(_ t: TransactionDetails) throws {
        var value = try loaded()
        guard var record = value.records[t.key] else { return }
        let fraction = t.revocationPercentage.map { NSDecimalNumber(decimal: $0).doubleValue / 100 } ?? 1
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
            throw StoreFailure(.verificationFailed, "退款比例无效，需要核对")
        }
        let target = fraction == 1 ? record.credited : min(record.credited, max(0, Int((Double(record.credited) * fraction).rounded(.up))))
        let additional = max(0, target - record.refundedCredits)
        let key = Self.balanceKey(t)
        let available = value.balances[key] ?? 0
        let deduction = min(available, additional)
        if record.credited > 0 { value.balances[key] = available - deduction }
        record.refundShortfall += additional - deduction
        record.refundedCredits += additional
        record.revoked = true; record.lastFailure = nil; record.nextRetryAt = nil
        record.revocationProcessedAt = t.signedDate
        record.revocationRevision = t.revocationKey
        value.records[t.key] = record
        value.pendingProducts.remove(t.productID)
        try commit(value)
    }
    public func markFinished(_ key: String) throws {
        var value = try loaded()
        value.records[key]?.finished = true
        value.records[key]?.lastFailure = nil
        value.records[key]?.nextRetryAt = nil
        value.records[key]?.attempts = 0
        try commit(value)
    }
    public func markFailure(_ key: String, _ failure: StoreFailure) throws {
        var value = try loaded()
        value.records[key]?.lastFailure = failure
        let attempts = value.records[key]?.attempts ?? 0
        let automatic = ![StoreFailure.Code.configuration, .verificationFailed, .unsupportedCapability, .offerInvalid].contains(failure.code)
        value.records[key]?.nextRetryAt = automatic && attempts < 5 ? Date().addingTimeInterval(30 * pow(2, Double(min(attempts, 6)))) : nil
        try commit(value)
    }
    public func consume(balanceKey: String, amount: Int) throws {
        var value = try loaded()
        guard amount > 0, (value.balances[balanceKey] ?? 0) >= amount else { throw StoreFailure(.configuration, "可用额度不足") }
        value.balances[balanceKey, default: 0] -= amount
        try commit(value)
    }
    public static func balanceKey(_ t: TransactionDetails) -> String { "\(t.bundleID)|\(t.environment)|\(t.productID)" }
}
