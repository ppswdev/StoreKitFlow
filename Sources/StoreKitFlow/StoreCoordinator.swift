import Foundation

struct StoreObservation: Sendable { let snapshot: StoreSnapshot; let event: StoreEvent? }

actor StoreCoordinator {
    let configuration: StoreConfiguration
    let gateway: any StoreGateway
    let ledger: DeliveryLedger
    private let delivery: (any DeliveryHandler)?
    private let validator: (any TransactionValidator)?
    private let now: @Sendable () -> Date
    private var snapshot = StoreSnapshot()
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0
    private var subscribers: [UUID: AsyncStream<StoreObservation>.Continuation] = [:]
    private var startTask: Task<Void, any Error>?
    private var listener: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshDirty = false
    private var productTask: Task<[ProductDetails], any Error>?
    private var inFlight: [String: (id: UUID, task: Task<StoreFailure?, Never>)] = [:]
    private var purchasing = false
    private var restoring = false

    deinit {
        listener?.cancel(); timer?.cancel(); startTask?.cancel()
        refreshTask?.cancel(); productTask?.cancel()
        subscribers.values.forEach { $0.finish() }
    }

    init(configuration: StoreConfiguration, gateway: any StoreGateway,
         delivery: (any DeliveryHandler)?, validator: (any TransactionValidator)?, now: @escaping @Sendable () -> Date) {
        self.configuration = configuration; self.gateway = gateway; self.delivery = delivery
        self.validator = validator; self.now = now
        ledger = DeliveryLedger(url: configuration.storageURL)
    }
    func observations() -> AsyncStream<StoreObservation> {
        let id = UUID()
        let pair = AsyncStream<StoreObservation>.makeStream(bufferingPolicy: .bufferingNewest(256))
        subscribers[id] = pair.continuation
        pair.continuation.yield(StoreObservation(snapshot: snapshot, event: nil))
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        return pair.stream
    }
    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }
    private func publish(_ kind: StoreEvent.Kind? = nil, product: String? = nil,
                         transaction: String? = nil, operation: UUID? = nil, failure: StoreFailure? = nil) {
        snapshot.revision += 1
        if let failure { snapshot.lastFailure = failure }
        var event: StoreEvent?
        if let kind {
            sequence += 1
            event = StoreEvent(id: UUID(), sequence: sequence, kind: kind, snapshotRevision: snapshot.revision,
                               productID: product, transactionKey: transaction, operationID: operation, failure: failure)
        }
        let update = StoreObservation(snapshot: snapshot, event: event)
        for continuation in subscribers.values {
            if case .dropped = continuation.yield(update) {
                let gap = StoreEvent(id: UUID(), sequence: sequence, kind: .eventGapDetected,
                    snapshotRevision: snapshot.revision, productID: nil, transactionKey: nil, operationID: nil, failure: nil)
                continuation.yield(StoreObservation(snapshot: snapshot, event: gap))
            }
        }
    }
    func currentSnapshot() -> StoreSnapshot { snapshot }

    func start() async throws {
        if let startTask { return try await startTask.value }
        if snapshot.lifecycle == .ready { return }
        try configuration.validate()
        generation += 1
        let version = generation
        snapshot.lifecycle = .starting; snapshot.lastFailure = nil; publish()
        let task = Task { try await self.bootstrap(version) }
        startTask = task
        do { try await task.value; if generation == version { startTask = nil } }
        catch {
            if generation == version { await stop(); snapshot.lastFailure = .wrap(error); publish(.error, failure: .wrap(error)) }
            throw error
        }
    }
    private func bootstrap(_ version: UInt64) async throws {
        let stream = await gateway.updates()
        guard generation == version else { throw CancellationError() }
        listener = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled else { break }
                await self?.handle(update, generation: version)
            }
        }
        try await updateLedgerSnapshot()
        guard generation == version else { throw CancellationError() }
        async let catalog: Void = initialCatalog()
        await recoverTransactions()
        await refreshEntitlements()
        await catalog
        try Task.checkCancellation()
        guard generation == version else { throw CancellationError() }
        snapshot.lifecycle = .ready
        publish(.started)
        scheduleRefresh()
    }
    private func initialCatalog() async {
        do { _ = try await refreshProducts() } catch { /* refreshProducts publishes its own failure. */ }
    }
    func stop() async {
        generation += 1
        startTask?.cancel(); startTask = nil
        listener?.cancel(); listener = nil
        timer?.cancel(); timer = nil
        refreshTask?.cancel(); refreshTask = nil
        productTask?.cancel(); productTask = nil
        await gateway.stop()
        let revision = snapshot.revision
        snapshot = StoreSnapshot()
        snapshot.revision = revision
        publish(.stopped)
    }
    private func requireStarted() throws {
        guard snapshot.lifecycle != .stopped else { throw StoreFailure(.notStarted, "请先调用 start()") }
    }
    func refreshProducts() async throws -> [ProductDetails] {
        try requireStarted()
        if let productTask { return try await productTask.value }
        let version = generation
        let ids = configuration.products.map(\.id)
        let task = Task { try await gateway.products(for: ids) }
        productTask = task
        do {
            let products = try await task.value
            guard version == generation else { throw CancellationError() }
            productTask = nil
            let definitions = Dictionary(uniqueKeysWithValues: configuration.products.map { ($0.id, $0) })
            snapshot.products = products.filter { product in
                if definitions[product.id]?.kind != product.kind {
                    snapshot.lastFailure = .init(.configuration, "商品类型与配置不同：\(product.id)")
                    return false
                }
                return true
            }
            snapshot.missingProductIDs = ids.filter { id in !snapshot.products.contains { $0.id == id } }
            snapshot.catalogIsStale = false
            publish(.productsUpdated)
            return snapshot.products
        } catch {
            if generation == version { productTask = nil; snapshot.catalogIsStale = true; publish(.error, failure: .wrap(error)) }
            throw error
        }
    }
    func refreshEntitlements() async {
        guard snapshot.lifecycle != .stopped else { return }
        if let refreshTask { refreshDirty = true; await refreshTask.value; return }
        let version = generation
        let task = Task { await self.refreshLoop(version) }
        refreshTask = task
        await task.value
        if version == generation { refreshTask = nil; scheduleRefresh() }
    }
    private func refreshLoop(_ version: UInt64) async {
        repeat {
            refreshDirty = false
            let groups = Set(configuration.products.compactMap(\.groupID) + snapshot.products.compactMap(\.groupID))
            var evidence = await gateway.evidence(groupIDs: groups)
            guard generation == version, !Task.isCancelled else { return }
            if let validator {
                var seen: Set<String> = []
                for transaction in evidence.current + evidence.history + evidence.subscriptions.map(\.transaction) {
                    guard seen.insert(transaction.key).inserted else { continue }
                    do { try await validator.validate(transaction) }
                    catch { evidence.rejectedKeys.insert(transaction.key); evidence.complete = false; evidence.issues.append(.wrap(error)) }
                }
            }
            // Restored non-consumables and historical non-renewing terms also go through delivery.
            // Never replay finished consumable history as new credit.
            let candidates = evidence.current + evidence.history.filter { $0.kind == .nonRenewable }
            for transaction in candidates where transaction.kind != .consumable && !evidence.rejectedKeys.contains(transaction.key) {
                guard configuration.products.contains(where: { $0.id == transaction.productID }) else { continue }
                let record = try? await ledger.record(for: transaction.key)
                if record == nil || (record?.delivered == false && record?.lastFailure == nil) {
                    if let failure = await process(transaction) {
                        evidence.rejectedKeys.insert(transaction.key); evidence.complete = false; evidence.issues.append(failure)
                    }
                }
            }
            if let records = try? await ledger.records() {
                for record in records where !record.delivered && !record.revoked {
                    evidence.rejectedKeys.insert(record.id); evidence.complete = false
                }
            }
            // Process revocation revisions even for transactions that were delivered before this launch.
            for t in evidence.history where t.revocationDate != nil {
                if let record = try? await ledger.record(for: t.key),
                   record.revocationRevision != t.revocationKey, retryAllows(record, transaction: t) { _ = await process(t) }
            }
            guard generation == version, !Task.isCancelled else { return }
            let old = snapshot.entitlements
            // A device clock rollback cannot extend an entitlement already evaluated in this process.
            let evaluatedAt = max(now(), old.pro.evaluatedAt)
            let new = EntitlementResolver.resolve(evidence, configuration: configuration, now: evaluatedAt, previous: old)
            let changedSubscriptions = snapshot.subscriptions != evidence.subscriptions
            snapshot.entitlements = new
            snapshot.entitlementIssues = evidence.issues
            snapshot.subscriptions = evidence.subscriptions
            if let failure = evidence.issues.first { snapshot.lastFailure = failure }
            publish(.entitlementsChanged)
            if old.pro.access != new.pro.access || old.pro.sources != new.pro.sources || old.pro.isStale != new.pro.isStale { publish(.proStatusChanged) }
            if changedSubscriptions { publish(.subscriptionStatusChanged) }
        } while refreshDirty && !Task.isCancelled && generation == version
    }
    private func scheduleRefresh() {
        timer?.cancel()
        guard snapshot.lifecycle != .stopped else { return }
        let deadline = snapshot.entitlements.nextEvaluationAt?.timeIntervalSince(now()) ?? configuration.retryInterval
        let delay = max(1, min(configuration.retryInterval, deadline))
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.recoverTransactions()
            await self?.refreshEntitlements()
        }
    }
    private func handle(_ update: GatewayUpdate, generation version: UInt64) async {
        guard generation == version else { return }
        switch update {
        case .transaction(let transaction):
            _ = await process(transaction)
            await refreshEntitlements()
        case .changed: await refreshEntitlements()
        case .storefrontChanged:
            snapshot.catalogIsStale = true; publish(.storefrontChanged)
            _ = try? await refreshProducts()
            await refreshEntitlements()
        case .failure(let error): publish(.error, failure: error)
        case .purchaseIntent(let intent): snapshot.purchaseIntent = intent; publish(.purchaseIntent, product: intent.productID)
        }
    }
    func purchase(_ request: PurchaseRequest) async throws -> PurchaseOutcome {
        try requireStarted()
        guard !purchasing else { throw StoreFailure(.operationInProgress, "已有购买正在处理") }
        guard let definition = configuration.products.first(where: { $0.id == request.productID }),
              request.quantity > 0, (definition.kind == .consumable || request.quantity == 1) else {
            throw StoreFailure(.configuration, "商品或购买数量无效")
        }
        purchasing = true; snapshot.activeOperation = request.operationID
        let version = generation
        publish(.purchaseStarted, product: request.productID, operation: request.operationID)
        defer { purchasing = false; if version == generation { snapshot.activeOperation = nil; publish() } }
        do {
            var checkedRequest = request
            checkedRequest.expectedKind = definition.kind
            let result = try await gateway.purchase(checkedRequest)
            guard version == generation else { throw CancellationError() }
            return try await completePurchase(result, request: request)
        } catch {
            let failure = StoreFailure.wrap(error)
            if version == generation { publish(.purchaseFailed, product: request.productID, operation: request.operationID, failure: failure) }
            throw failure
        }
    }
    func completePurchase(_ result: GatewayPurchaseResult, request: PurchaseRequest) async throws -> PurchaseOutcome {
        try requireStarted()
        let version = generation
        if snapshot.purchaseIntent?.productID == request.productID { snapshot.purchaseIntent = nil }
        switch result {
        case .pending:
            try await ledger.setPending(request.productID, pending: true)
            guard version == generation else { throw CancellationError() }
            snapshot.pendingProductIDs.insert(request.productID)
            publish(.purchasePending, product: request.productID, operation: request.operationID)
            return .pending(productID: request.productID)
        case .userCancelled:
            publish(.purchaseCancelled, product: request.productID, operation: request.operationID)
            return .userCancelled
        case .transaction(let transaction):
            let failure = await process(transaction)
            guard version == generation else { throw CancellationError() }
            await refreshEntitlements()
            if let failure { return .processing(transaction, failure) }
            publish(.purchaseCompleted, product: request.productID, transaction: transaction.key, operation: request.operationID)
            return .completed(transaction)
        }
    }
    func process(_ transaction: TransactionDetails) async -> StoreFailure? {
        guard snapshot.lifecycle != .stopped else { return StoreFailure(.notStarted, "服务未启动，交易将在下次启动恢复") }
        if let flight = inFlight[transaction.key] {
            _ = await flight.task.value
            if inFlight[transaction.key]?.id == flight.id { inFlight[transaction.key] = nil }
            // Re-evaluate a newer revision instead of losing a refund arriving during delivery.
            if let record = try? await ledger.record(for: transaction.key),
               record.transaction.signedDate >= transaction.signedDate,
               (transaction.revocationDate == nil || record.revocationRevision == transaction.revocationKey) { return record.lastFailure }
            return await process(transaction)
        }
        let task = Task { await self.performTransaction(transaction) }
        let id = UUID()
        inFlight[transaction.key] = (id, task)
        let result = await task.value
        if inFlight[transaction.key]?.id == id { inFlight[transaction.key] = nil }
        return result
    }
    private func performTransaction(_ transaction: TransactionDetails) async -> StoreFailure? {
        let version = generation
        do {
            guard let definition = configuration.products.first(where: { $0.id == transaction.productID }),
                  definition.kind == transaction.kind else { throw StoreFailure(.configuration, "未配置的商品交易，需要人工核对") }
            try await validator?.validate(transaction)
            let record = try await ledger.observe(transaction)
            let t = record.transaction
            if t.revocationDate != nil {
                let revisionKey = t.revocationKey!
                if record.revocationRevision != revisionKey {
                    try await delivery?.revoke(t, idempotencyKey: revisionKey)
                    try await ledger.markRevoked(t)
                    try await updateLedgerSnapshot()
                    if version == generation { publish(.entitlementRevoked, product: t.productID, transaction: t.key) }
                }
            } else if !record.delivered {
                try await delivery?.deliver(t, idempotencyKey: t.key)
                try await ledger.markDelivered(t, credits: definition.credits)
                try await updateLedgerSnapshot()
                if version == generation { publish(.deliveryCompleted, product: t.productID, transaction: t.key) }
            }
            await gateway.finish(t)
            try await ledger.markFinished(t.key)
            try await updateLedgerSnapshot()
            if version == generation { publish(.transactionFinished, product: t.productID, transaction: t.key) }
            return nil
        } catch {
            let failure = StoreFailure.wrap(error)
            try? await ledger.markFailure(transaction.key, failure)
            try? await updateLedgerSnapshot()
            if version == generation { publish(.deliveryDeferred, product: transaction.productID, transaction: transaction.key, failure: failure) }
            return failure
        }
    }
    func recoverTransactions() async {
        guard snapshot.lifecycle != .stopped else { return }
        do {
            let unfinished = try await gateway.unfinished()
            for transaction in unfinished {
                if let record = try await ledger.record(for: transaction.key), !retryAllows(record, transaction: transaction) { continue }
                _ = await process(transaction)
            }
            // A confirmed external delivery may outlive the StoreKit unfinished enumeration.
            let records = try await ledger.records()
            for record in records where !record.finished && !unfinished.contains(where: { $0.key == record.id }) {
                if !retryAllows(record, transaction: record.transaction) { continue }
                _ = await process(record.transaction)
            }
            try await updateLedgerSnapshot()
        } catch { publish(.error, failure: .wrap(error)) }
    }
    private func updateLedgerSnapshot() async throws {
        let version = generation
        let records = try await ledger.records()
        let balances = try await ledger.balances()
        let pending = try await ledger.pendingProducts()
        guard version == generation, snapshot.lifecycle != .stopped else { return }
        snapshot.deliveries = records; snapshot.balances = balances; snapshot.pendingProductIDs = pending
    }
    private func retryAllows(_ record: DeliveryRecord, transaction: TransactionDetails) -> Bool {
        record.lastFailure == nil || record.transaction.revocationKey != transaction.revocationKey ||
            record.nextRetryAt.map { $0 <= Date() } == true
    }
    func restore() async throws -> RestoreReport {
        try requireStarted()
        guard !restoring else { throw StoreFailure(.operationInProgress, "恢复购买正在进行") }
        restoring = true; defer { restoring = false }
        let version = generation
        publish(.restoreStarted)
        do {
            try await gateway.sync()
            guard version == generation else { throw CancellationError() }
            await recoverTransactions()
            await refreshEntitlements()
            publish(.restoreCompleted)
            return RestoreReport(entitlements: snapshot.entitlements,
                pendingDeliveries: snapshot.deliveries.filter { !$0.finished }.count,
                issues: snapshot.entitlementIssues + snapshot.deliveries.compactMap(\.lastFailure))
        } catch { let failure = StoreFailure.wrap(error); if version == generation { publish(.restoreFailed, failure: failure) }; throw failure }
    }
    func history() async throws -> [TransactionDetails] { try requireStarted(); return try await gateway.history() }
    func retry(_ key: String) async throws {
        try requireStarted()
        guard let record = try await ledger.record(for: key) else { throw StoreFailure(.configuration, "找不到订单") }
        if let failure = await process(record.transaction) { throw failure }
        await refreshEntitlements()
    }
    func consume(_ key: String, amount: Int) async throws {
        try requireStarted(); try await ledger.consume(balanceKey: key, amount: amount)
        try await updateLedgerSnapshot(); publish()
    }
    func presentationEvent(_ kind: StoreEvent.Kind) { publish(kind) }
}
