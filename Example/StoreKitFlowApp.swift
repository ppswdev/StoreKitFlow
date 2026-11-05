import SwiftUI
import StoreKitFlow

enum DemoConfiguration {
    static let products: [ProductDefinition] = [
        .init("com.ppswdev.store.goldcoin.10", kind: .consumable, credits: 10),
        .init("com.ppswdev.store.lifetimevip", kind: .nonConsumable, entitlements: ["pro"]),
        .init("com.ppswdev.store.lifetimevip2", kind: .nonConsumable, entitlements: ["pro"]),
        .init("com.ppswdev.store.non.monthlyvip", kind: .nonRenewable, entitlements: ["pro"], term: Term(1, .month)),
        .init("com.ppswdev.store.inapp.weeklyvip", kind: .autoRenewable, entitlements: ["pro"]),
        .init("com.ppswdev.store.inapp.monthlyvip", kind: .autoRenewable, entitlements: ["pro"]),
        .init("com.ppswdev.store.inapp.yearlyvip", kind: .autoRenewable, entitlements: ["pro"])
    ]
    @MainActor static func previewClient() -> StoreClient {
        let names = ["10 金币", "终身 Pro", "永久扩展", "一个月通行证", "Pro 周订阅", "Pro 月订阅", "Pro 年订阅"]
        let catalog = zip(products, names).map { ProductDetails.preview(id: $0.0.id, kind: $0.0.kind, name: $0.1) }
        return StoreClient(configuration: StoreConfiguration(products: products,
            storageURL: URL.temporaryDirectory.appending(path: "StoreKitFlow-preview/\(UUID())/ledger.json")),
            gateway: PreviewStoreGateway(products: catalog))
    }
    @MainActor static func appClient() -> StoreClient {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return previewClient() }
        #endif
        return StoreClient(configuration: StoreConfiguration(products: products))
    }
}

@main struct StoreKitFlowApp: App {
    @State private var store = DemoConfiguration.appClient()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            StoreDemoView(store: store)
                .task { if ProcessInfo.processInfo.environment["STOREKITFLOW_TEST_HOST"] != "1" { try? await store.start() } }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await store.refreshOnForeground() } }
                }
        }
    }
}

struct StoreDemoView: View {
    var store: StoreClient
    @State private var scene: UIWindowScene?
    @State private var message: String?
    @State private var events: [StoreEvent] = []
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview") {
                    Text("离线预览 · 模拟商品数据").font(.caption).foregroundStyle(.secondary)
                }
                #endif
                Section("Pro 权益") {
                    Label(proTitle, systemImage: store.isPro ? "checkmark.seal.fill" : "person.crop.circle")
                        .foregroundStyle(store.isPro ? .green : .primary)
                    Text(store.proStatus.reason).font(.caption).foregroundStyle(.secondary)
                    if store.proStatus.isStale { Text("部分信息待核实，请联网后刷新").font(.caption).foregroundStyle(.orange) }
                    ForEach(store.proStatus.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.productID).font(.caption)
                            if let end = source.validUntil { Text("有效至 \(end.formatted())").font(.caption2) }
                            else { Text("永久权益").font(.caption2) }
                            Text("\(source.reason) · \(source.ownership.rawValue)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if let failure = store.snapshot.lastFailure {
                    Section("最近诊断") {
                        Text(failure.message).foregroundStyle(.orange)
                        Button("重新检查") { Task { await store.refreshOnForeground() } }
                    }
                }
                ForEach(ProductKind.allCases.filter { $0 != .unsupported }, id: \.self) { kind in
                    Section(title(kind)) {
                        ForEach(store.products.filter { $0.kind == kind }) { product in
                            NavigationLink {
                                ProductDetailView(store: store, product: product, scene: scene)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName)
                                        Text(product.id).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                }
                            }
                        }
                    }
                }
                if !store.snapshot.missingProductIDs.isEmpty {
                    Section("当前未返回的商品") { ForEach(store.snapshot.missingProductIDs, id: \.self) { Text($0).font(.caption) } }
                }
                if !store.snapshot.pendingProductIDs.isEmpty {
                    Section("等待批准或外部完成") {
                        ForEach(Array(store.snapshot.pendingProductIDs).sorted(), id: \.self) { Text($0).font(.caption) }
                        Text("批准后会自动处理；没有新结果不代表 Apple 已拒绝。").font(.caption2)
                    }
                }
                if let intent = store.snapshot.purchaseIntent {
                    Section("来自商店的购买意向") {
                        Text(intent.productID).font(.caption)
                        if let offer = intent.offerDetails { Text("\(offer.type) · \(offer.displayPrice)") }
                        Button("确认并继续购买") {
                            run {
                                store.setPurchaseScene(scene)
                                let result = try await store.purchase(.init(productID: intent.productID, offer: intent.offer))
                                switch result {
                                case .completed: return "购买和交付已完成"
                                case .pending: return "等待批准"
                                case .userCancelled: return "已取消本次购买"
                                case .processing(_, let failure): return "权益处理中：\(failure.message)"
                                }
                            }
                        }.disabled(store.snapshot.activeOperation != nil)
                    }
                }
                Section("消耗品账本") {
                    if store.snapshot.balances.isEmpty { Text("尚无金币余额").foregroundStyle(.secondary) }
                    ForEach(store.snapshot.balances.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading) {
                            Text("可用额度：\(store.snapshot.balances[key] ?? 0)")
                            Text(key).font(.caption2).foregroundStyle(.secondary)
                            Button("使用 1 次") { run { try await store.consume(balanceKey: key, amount: 1); return "已使用 1 次" } }
                                .disabled((store.snapshot.balances[key] ?? 0) == 0)
                        }
                    }
                }
                Section("账户与订单") {
                    Button(restoring ? "正在恢复…" : "恢复购买") {
                        restoring = true
                        Task {
                            defer { restoring = false }
                            do {
                                let report = try await store.restorePurchases()
                                message = report.entitlements.pro.access == .active ? "已读取有效 Pro 权益" : "同步完成，当前没有确认的 Pro 权益"
                                if report.pendingDeliveries > 0 { message! += "；还有 \(report.pendingDeliveries) 笔订单待处理" }
                            } catch { message = error.localizedDescription }
                        }
                    }.disabled(restoring)
                    Button("管理订阅 / 取消自动续订") {
                        run { guard let scene else { throw missingScene }; try await store.manageSubscriptions(in: scene); return "已刷新订阅状态" }
                    }
                    Button("兑换优惠码") {
                        run { guard let scene else { throw missingScene }; try await store.redeemOfferCode(in: scene); return "兑换界面已关闭，权益已重新检查" }
                    }
                    NavigationLink("交易历史与退款") { HistoryView(store: store, scene: scene) }
                    NavigationLink("交付记录与补单") { DeliveryView(store: store) }
                    Button("刷新商品") { run { _ = try await store.refreshProducts(); return "商品列表已刷新" } }
                }
                #if DEBUG
                Section("事件时间线") {
                    ForEach(events.prefix(40)) { event in
                        Text("#\(event.sequence) \(event.kind.rawValue)").font(.caption.monospaced())
                    }
                }
                #endif
            }
            .navigationTitle("StoreKitFlow")
            .background(SceneReader { value in scene = value; store.setPurchaseScene(value) }.frame(width: 0, height: 0))
            .task { for await event in store.events() { events.insert(event, at: 0); if events.count > 100 { events.removeLast() } } }
            .alert("操作结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }
    private var missingScene: StoreFailure { .init(.presentationUnavailable, "窗口未就绪") }
    private var proTitle: String { switch store.proStatus.access { case .active: "Pro 已激活"; case .inactive: "尚无 Pro 权益"; case .unknown: "正在核实 Pro 权益" } }
    private func title(_ kind: ProductKind) -> String {
        switch kind { case .consumable: "消耗品"; case .nonConsumable: "永久解锁"; case .nonRenewable: "非续订订阅"; case .autoRenewable: "自动续订订阅"; case .unsupported: "暂不支持" }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> String) {
        Task { do { message = try await operation() } catch { message = error.localizedDescription } }
    }
}

struct ProductDetailView: View {
    var store: StoreClient
    let initialProduct: ProductDetails
    let scene: UIWindowScene?
    @State private var message: String?
    @State private var selectedOffer: String = "automatic"
    @State private var quantity = 1
    @State private var languageCode = "zh_Hans"
    init(store: StoreClient, product: ProductDetails, scene: UIWindowScene?) {
        self.store = store; initialProduct = product; self.scene = scene
    }
    private var product: ProductDetails { store.products.first { $0.id == initialProduct.id } ?? initialProduct }
    private var alreadyOwned: Bool { product.kind == .nonConsumable && store.snapshot.entitlements.grants.contains { $0.productID == product.id } }
    private var legacyPeriod: SubscriptionPeriodType? {
        if product.kind == .nonConsumable { return .lifetime }
        guard product.kind == .autoRenewable, product.periodValue == 1 else { return nil }
        switch product.periodUnit { case "week": return .week; case "month": return .month; case "year": return .year; default: return nil }
    }
    var body: some View {
        List {
            Section("商品详情") {
                Text(product.description)
                LabeledContent("价格", value: product.displayPrice)
                LabeledContent("类型", value: product.kind.rawValue)
                LabeledContent("货币", value: product.currencyCode ?? "未提供")
                LabeledContent("家庭共享", value: product.familyShareable ? "支持" : "不支持")
                if let value = product.periodValue, let unit = product.periodUnit { LabeledContent("订阅周期", value: "\(value) \(unit)") }
                if let group = product.groupID { LabeledContent("订阅组", value: group) }
            }
            if let legacyPeriod {
                Section("原版多语言文案") {
                    Picker("语言", selection: $languageCode) {
                        Text("简体中文").tag("zh_Hans")
                        Text("繁體中文").tag("zh_Hant")
                        Text("English").tag("en")
                        Text("Deutsch").tag("de")
                    }
                    LabeledContent("标题", value: SubscriptionLocale.subscriptionTitle(periodType: legacyPeriod, languageCode: languageCode))
                    LabeledContent("按钮", value: SubscriptionLocale.subscriptionButtonText(type: legacyPeriod == .lifetime ? .lifetime : .standard, languageCode: languageCode))
                }
            }
            Section("购买方案") {
                if product.kind == .consumable { Stepper("数量：\(quantity)", value: $quantity, in: 1...10) }
                Picker("方案", selection: $selectedOffer) {
                    Text("标准购买 / 系统适用的介绍性优惠").tag("automatic")
                    ForEach(product.offers.filter { $0.type == "winBack" && $0.eligibility == .eligible }) { offer in
                        Text("召回优惠：\(offer.displayPrice)").tag(offer.id)
                    }
                }
                Button(alreadyOwned ? "已拥有此永久权益" : "购买 · \(selectedOffer == "automatic" ? product.displayPrice : "所选优惠")") {
                    Task {
                        do {
                            store.setPurchaseScene(scene)
                            let result = try await store.purchase(.init(productID: product.id, quantity: quantity, offer: selectedOffer == "automatic" ? .automatic : .winBack(id: selectedOffer)))
                            switch result {
                            case .completed: message = "购买和交付已完成"
                            case .pending: message = "等待批准，完成后会自动处理"
                            case .userCancelled: message = "已取消本次购买"
                            case .processing(_, let failure): message = "交易已确认，权益处理中：\(failure.message)"
                            }
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(store.snapshot.activeOperation != nil || alreadyOwned || store.snapshot.catalogIsStale)
                Text("展示价格为单件标准价格；适用试用、优惠和总价以系统确认页为准。").font(.caption2).foregroundStyle(.secondary)
            }
            Section("全部优惠信息") {
                if product.offers.isEmpty { Text("商店未提供优惠") }
                ForEach(product.offers) { offer in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(offer.type) · \(offer.displayPrice)")
                        Text("\(offer.periodValue) \(offer.periodUnit) × \(offer.periodCount) · \(offer.paymentMode)").font(.caption)
                        Text("资格：\(offer.eligibility.rawValue)").font(.caption).foregroundStyle(.secondary)
                        if offer.eligibility == .requiresSignature { Text("促销购买需要签名服务；当前示例未配置。").font(.caption2) }
                    }
                }
            }
            Section("当前订阅状态") {
                ForEach(Array(store.snapshot.subscriptions.filter { $0.transaction.productID == product.id }.enumerated()), id: \.offset) { _, status in
                    VStack(alignment: .leading) {
                        Text(status.state.rawValue)
                        Text("自动续订：\(status.willAutoRenew.map { $0 ? "开启" : "关闭" } ?? "未知")").font(.caption)
                        if let end = status.gracePeriodExpirationDate { Text("宽限至 \(end.formatted())").font(.caption) }
                        if let next = status.autoRenewPreference { Text("下期产品：\(next)").font(.caption) }
                    }
                }
            }
            Section("原始商品信息") {
                Text(String(data: product.rawJSON, encoding: .utf8) ?? "预览数据").font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .navigationTitle(product.displayName)
        .alert("购买结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

struct HistoryView: View {
    var store: StoreClient
    let scene: UIWindowScene?
    @State private var transactions: [TransactionDetails] = []
    @State private var message: String?
    var body: some View {
        List {
            if transactions.isEmpty { Text("没有可显示的历史交易") }
            ForEach(transactions) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.productID)
                    Text("订单 \(t.id) · \(t.environment)").font(.caption).textSelection(.enabled)
                    Text(t.purchaseDate.formatted()).font(.caption)
                    if let end = t.expirationDate { Text("到期：\(end.formatted())").font(.caption) }
                    if t.revocationDate != nil { Text("此授权已撤销").foregroundStyle(.orange) }
                    Button("申请退款") {
                        Task {
                            do {
                                guard let scene else { throw StoreFailure(.presentationUnavailable, "窗口未就绪") }
                                let result = try await store.requestRefund(transactionID: t.id, in: scene)
                                message = result == .requestSubmitted ? "退款申请已提交，审批结果由 Apple 决定" : "已取消退款申请"
                            } catch { message = error.localizedDescription }
                        }
                    }.disabled(t.revocationDate != nil)
                }
            }
        }.navigationTitle("历史与退款")
        .task { do { transactions = try await store.transactionHistory() } catch { message = error.localizedDescription } }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}
struct DeliveryView: View {
    var store: StoreClient
    @State private var message: String?
    var body: some View {
        List(store.snapshot.deliveries) { record in
            VStack(alignment: .leading, spacing: 6) {
                Text(record.transaction.productID)
                Text("交付：\(record.delivered ? "已确认" : "待处理") · 交易：\(record.finished ? "已结束" : "未结束")").font(.caption)
                if record.refundShortfall > 0 { Text("退款额度差额：\(record.refundShortfall)").font(.caption) }
                if let failure = record.lastFailure { Text(failure.message).font(.caption).foregroundStyle(.orange) }
                if !record.finished {
                    Button("重试交付") { Task { do { try await store.retryDelivery(for: record.id) } catch { message = error.localizedDescription } } }
                }
            }
        }.navigationTitle("交付与补单")
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

struct SceneReader: UIViewRepresentable {
    let onScene: @MainActor (UIWindowScene?) -> Void
    final class SceneView: UIView {
        var onScene: (@MainActor (UIWindowScene?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onScene?(window?.windowScene) }
    }
    func makeUIView(context: Context) -> SceneView { let view = SceneView(); view.onScene = onScene; return view }
    func updateUIView(_ view: SceneView, context: Context) { view.onScene = onScene }
}

#Preview {
    let store = DemoConfiguration.previewClient()
    StoreDemoView(store: store).task { try? await store.start() }
}
