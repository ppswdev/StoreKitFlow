# StoreKitFlow 2.0 接入与业务规则

本页描述已实现的 API。产品名 `StoreKitFlow`，公开入口 `StoreClient`，Swift 6 language mode。主线 iOS/iPadOS 17+；macOS 14+ 为核心库，UIKit 的管理/退款/兑换入口和示例仅用于 iOS。

## 1. 初始化和生命周期

在 SwiftUI App 根部使用 `@State` 持有一个 `StoreClient`，通过环境或构造参数传给页面。`StoreClient` 是 `@MainActor @Observable`，协调器和账本分别使用 actor。库不强制全局单例。

```swift
import SwiftUI
import StoreKitFlow

@MainActor
struct Paywall: View {
    let store: StoreClient

    var body: some View {
        List(store.products) { product in
            Text("\(product.displayName) · \(product.displayPrice)")
        }
        .task { try? await store.start() }
    }
}
```

完整 App 与 Scene 获取方式见 `Example/StoreKitFlowApp.swift`。正式应用应按 UI 需求展示 `start()` 抛出的配置或持久化错误；示例通过 `snapshot.lastFailure` 展示诊断。

| 方法 | 行为 |
|---|---|
| `start()` | 验证配置、先监听、读账本、恢复未完成交易、读取商品和权益；并发启动共用同一任务 |
| `stop()` | 取消监听/调度并重置为 unknown；已付款的交付可能完成持久化，迟到结果不恢复停止后的 Pro |
| `refreshOnForeground()` | 补单、重算权益，必要时刷新失效目录 |
| `refreshEntitlements()` | 主动核对当前权益、历史及全部相关组状态，不弹恢复认证 |
| `refreshProducts()` | 合并并发目录请求，保持配置 ID 顺序，返回有效商品 |
| `restorePurchases()` | 用户主动触发的 `AppStore.sync()`，随后补单和核对，返回权益、待交付数和本次问题 |

启动不会调用 `AppStore.sync()`。相同 client 不支持原地修改配置；需要重新配置时先 `stop()`，再建立新 client。不要为每个付费页建立独立交易管理器；同一个账本路径只应有一个活动写入者，不用于多个 App Extension 并发写入。

`start()` 结束表示初始化流程结束，不保证网络正常或所有补单成功。检查 `snapshot.catalogIsStale`、`missingProductIDs`、`entitlementIssues`、`deliveries` 和 `proStatus`。

## 2. 配置和四类产品

```swift
let configuration = StoreConfiguration(products: [
    .init("app.coins10", kind: .consumable, credits: 10),
    .init("app.lifetime", kind: .nonConsumable, entitlements: ["pro"]),
    .init("app.monthly", kind: .autoRenewable, entitlements: ["pro"]),
    .init("app.monthpass", kind: .nonRenewable,
          entitlements: ["pro"], term: Term(1, .month), stacks: false)
], acceptsFamilySharing: true)
```

`entitlements` 可包含 `pro` 或任意业务功能 ID；用 `snapshot.entitlements.has("feature.id")` 查询。未映射的商品不自动成为 Pro。当前不做多等级会员推断，多来源有效权益取并集。

自动续订可配置 `groupID`，也会从商品和已验证交易发现组 ID。遍历全部状态，不取数组第一个。产品类型不匹配时从可购买目录排除并报告诊断。

非续订使用 Gregorian / UTC 日历日、月、年；一个月不固定等于 30 天。默认每笔购买独立起算，`stacks: true` 才从上一段有效结束时间顺延。按交易 ID 去重，退款后重算所有区间。修改已发布商品的期限和累加策略会改变历史计算，生产中应以新商品 ID 或明确的数据迁移表达规则变化。

消耗品余额按 `bundleID|environment|productID` 隔离，发放 `credits × purchasedQuantity`。调用：

```swift
try await store.consume(balanceKey: balanceKey, amount: 1)
```

余额是本地账本，不是把历史购买数量相加得到的。卸载、清理容器或换设备不会自动恢复已消费后的余额；如果业务需要跨设备钱包，接入服务端账本。Apple 账户切换不被本地钱包当作一个新的自有账号。

## 3. 商品详情和价格

`ProductDetails` 包含 ID、类型、原始类型、名称、描述、Decimal 价格、本地化价格、货币、家庭共享能力、订阅组/周期、所有 StoreKit 返回的介绍性/促销/召回优惠、资格和更新时间。

`rawJSON` 保存 Apple 的完整原始商品 JSON，未知字段不伪造为 0 或空字符串。若需要 SDK 新增但尚未投影的公开属性，使用：

```swift
let details = try await store.productDetails(for: productID)
let nativeProduct = try await store.storeKitProduct(for: productID)
```

`storeKitProduct` 只对 Apple Gateway 有意义；离线 Preview 不返回虚构原生 Product。原始 JSON 不是所有计算属性的替代品，异步资格等由 DTO 和原生 Product 补足。

商品部分缺失通过 `missingProductIDs` 告知，库不猜测审核、地区或商品配置原因。请求抛错时保留旧目录并标记 stale，不撤销有效 Pro。Storefront 改变会失效缓存并重新加载；购买前重新获取原生商品，防止复用旧商店对象。

价格使用 Decimal，不经 Double 中转；显示使用 StoreKit 的 `displayPrice`。免费试用、按期优惠、预付优惠区分 `paymentMode` 与 `periodCount`。本地展示不能代替系统购买确认页的最终价格和条款。

## 4. 购买和结果

iOS 购买须先通过 `setPurchaseScene(_:)` 指定用户操作所在的活跃 `UIWindowScene`。管理、退款、兑换直接传 scene；不要从多个窗口中任意选择一个。macOS 核心使用平台可用的 StoreKit 购买 API。

```swift
store.setPurchaseScene(scene)
let result = try await store.purchase(.init(productID: productID, quantity: 1))
switch result {
case .completed:
    // 交易验证、业务交付和本地记录均已确认；UI 读取快照。
    break
case .pending:
    // Ask to Buy 等等待状态；结束阻塞式 loading，不授予新权益。
    break
case .userCancelled:
    // 本次购买取消，已有会员权益不变。
    break
case .processing(_, let failure):
    // 支付交易已确认，但交付尚未完成；提示补单，不能再次自动扣款。
    print(failure.code) // 不打印整个交易或签名。
}
```

配置、商品不可用、支付受限、无活跃 scene、验证失败、优惠无效、网络和系统错误会抛 `StoreFailure`。`operationID` 用于关联事件。调用方 Task 取消不等于 Apple 已取消付款，后续仍从 updates/unfinished 对账。

同一个 client 同时只允许一个系统购买请求。消耗品 quantity 必须大于 0；其他类型必须为 1。示例对已拥有的永久权益展示“已拥有”，API 的重复交易仍走幂等交付。

`pendingProductIDs` 持久化的是“存在未确认的请求提示”，不是交易 ID 或付款证明。批准后交付会清除此商品的 pending；系统没有通知拒绝时不自行宣称失败，也不持续显示阻塞式 loading。

### 优惠与商店购买意向

| 选择 | 行为 |
|---|---|
| `.automatic` | 标准购买，介绍性优惠资格由 StoreKit 最终判断 |
| `.promotional(id:)` | 检查优惠存在，要求注入 OfferSigner 返回签名 JWS；签名或资格失败不回退原价 |
| `.winBack(id:)` | iOS 18/macOS 15+，检查可用优惠及已验证续订信息中的资格 |

`PurchaseIntent` 通过 `snapshot.purchaseIntent` 和 `.purchaseIntent` 事件交给 UI。保留原优惠选择，等待用户确认后传回相同 `offer` 购买；不收到意向就自动付款。未知优惠类型明确报不支持，不按原价替换。

原生 `StoreView` / `ProductView` / `SubscriptionStoreView` 的购买结果必须接回：

```swift
_ = try await store.processExternalPurchaseResult(result, productID: product.id)
```

它与普通购买使用相同账本和 finish 入口；不依赖 `Transaction.updates` 是否再次发送本机购买。应在显示原生 StoreKit 页面前完成 `start()`。

## 5. Pro 的确认规则

UI 始终读取 `proStatus`；`isPro` 只是 `access == .active` 的便利值。

| 证据 | Pro 行为 |
|---|---|
| 尚未初始化 / 核对不完整且无可信来源 | unknown；显示检查或重试，不说“已过期” |
| 完整核对且无有效 Pro 来源 | inactive |
| 映射 Pro 的非消耗品当前有效 | active，永久来源 |
| 订阅有效 / 试用有效 | active，直到该来源有效期结束 |
| 已取消自动续订 | 当前周期内继续 active |
| 有明确有效截止时间的宽限期 | active，截止时间使用宽限边界 |
| 纯扣款重试、到期、撤销 | 该来源不再授权 |
| 退款申请刚提交 | 保持原权益，等 StoreKit 的实际撤销证据 |
| 订阅退款但另有终身 Pro | 继续 active，移除被退款来源 |
| 非续订 | 按配置的业务期限和已验证历史计算 |
| 消耗品 | 不直接授予 Pro |
| 未验证、未知 ownership、不支持的新类型 | 不新增权限 |

`sources` 给出所有有效来源，`validUntil == nil` 可能表示永久来源；无来源时也为 nil，需结合 access 使用。`isStale` 表示证据不完整。`snapshot.entitlements.nextEvaluationAt` 是最早需要重算的期限，Pro 总有效期不等同于这个最早期限。

不完整刷新只保留仍在已知有效边界内、没有被新撤销证据排除的旧来源；完整空结果会清除旧权益。当前进程不会因设备时间回拨延长已经检查过的权益，但纯客户端不能提供跨重启的可信服务器时间或防篡改钱包保证。

状态监听、定时边界检查和前台刷新配合使用；iOS 挂起 App 后不保证后台实时回调。退款、撤销、换商店账号等变化在 StoreKit 提供新证据后反映，不能凭客户端猜测离线变化。

## 6. 交付、持久化与补单

流水线：验证 → 核对商品 → 可选验证器 → 原子写 observed → 幂等业务交付 → 原子写 delivered/余额 → `finish()` → 写 finished → 重算权益。

交易键为 `bundleID|environment|transactionID`。不用 originalID 去重续费；同一 originalID 下不同续费交易都处理。多个入口同时到达同交易会合并 in-flight Task；退款修订按撤销时间、类型和比例组成的业务版本继续处理，不被旧记录吞掉。

`DeliveryLedger` 使用 schema 1 的原子 JSON 文件，余额与发放标记一同提交。文件写入失败不把内存标记为成功。损坏或未知 schema 抛错，不删除重建。已交付未 finish 的记录在重启时只补 finish。当前没有旧持久化账本需要迁移；将来变更 schema 必须实现迁移。

重试只重试验证/交付/对账，绝不自动重新发起支付。可恢复交付错误按 60、120、240、480 秒退避，达到尝试上限或不可恢复错误后等待人工处理。`retryInterval` 控制后台检查间隔；权益期限到达会更早重算。手动调用：

```swift
try await store.retryDelivery(for: transactionKey)
```

退款补偿只扣剩余可用额度，已消费差额记录为 `refundShortfall`；对已观察到的部分退款比例累计补偿，重复通知不重复扣。组合商品的复杂部分撤销不是本轮支持类型。

## 7. 管理、退款与恢复

```swift
try await store.manageSubscriptions(in: scene)
let refund = try await store.requestRefund(transactionID: transaction.id, in: scene)
try await store.redeemOfferCode(in: scene)
let report = try await store.restorePurchases()
let history = try await store.transactionHistory()
```

管理界面关闭只产生 `.managementDismissed` 并刷新，不能当成“取消成功”。没有静默替用户取消自动续订的方法。

退款结果 `.requestSubmitted` 表示已提交申请，`.userCancelled` 表示用户关闭。申请不是审批成功；实际撤销由更新、历史或当前权益确认。恢复成功也不等于 Pro 必然存在，需读取 `RestoreReport`。

历史记录不是当前权益，也不是余额。示例的 `Config/Example-Info.plist` 设置了布尔型 `SKIncludeConsumableInAppPurchaseHistory`；接入 App 如需相应系统支持的已完成消耗品历史，应自行配置此键。

## 8. 状态快照与事件

`snapshot` 是 UI 的状态来源：生命周期、revision、商品/缺失 ID、权益/订阅、pending、activeOperation、余额、交付记录、诊断与购买意向。

```swift
for await event in store.events() {
    // 独立消费者；可记录埋点、提示结果，不能在这里再次发货。
    switch event.kind {
    case .proStatusChanged: updateFeaturesFromSnapshot()
    case .purchasePending: showPendingHint()
    default: break
    }
}
```

每个调用者得到独立广播订阅，事件包含 `sequence`、`snapshotRevision`、operationID、产品及交易键。快照先于对应事件对观察者可见；可能已经推进到更高 revision。慢消费者缓冲最多 256 条，检测 `.eventGapDetected` 或 sequence 间断后重新读取快照，不能用 UI 事件作为财务账本。停止服务结束订阅，再启动需重新订阅。

`deliveryCompleted` 表示业务交付；`transactionFinished` 表示调用 finish 后记录完成；`purchaseCompleted` 在权益核对后发出。Pro 变化看 `.proStatusChanged`，不能把任意交付事件当作 Pro=true。

库不默认打印日志；示例仅在 Debug 显示事件种类，不打印 JWS/token。错误中不要主动拼入敏感签名。

## 9. 可选后端接入

默认三项均为 nil，不访问任何业务服务器。提供自己的 `Sendable` actor 实现后注入构造器即可：

| 协议 | 契约 |
|---|---|
| `TransactionValidator.validate` | 已通过 StoreKit 验证后追加业务校验；失败不发新权益、不 finish |
| `DeliveryHandler.deliver/revoke` | 相同幂等键可重复调用，必须返回已确认的交付结果；异常/超时留在处理中 |
| `OfferSigner.signature` | 根据商品、优惠及可选 appAccountToken 返回促销签名 JWS；签名私钥只放在服务器 |

交易 DTO 保留 `signedJWS` 和可选 `appAccountToken` 供显式集成；不用设备 UUID 替代账号。没有自有账号时 token 默认 nil。未来账号归属校验可在 validator 中实现，但完整账号切换和跨设备钱包需要独立服务端设计与验收。

自定义服务应设置自己的请求超时，遵守取消并保持幂等；SDK 不强行超时重试已扣款请求。Apple Server API / Notifications V2 的部署和退款消费信息反馈不由客户端协议自动完成。

## 10. JSON、测试和能力边界

`StoreJSON.products(_:)`、`StoreJSON.transactions(_:)` 是纯转换，schemaVersion=1；Decimal 和交易 ID 用字符串，日期 ISO-8601，保留输入顺序。默认排除 signedJWS、account token 和原始交易 JSON。需要证据时由宿主显式读取 DTO，避免不经意导出。

Preview 显式注入 `PreviewStoreGateway`，不会自动 fallback 到假数据；可以模拟目录、证据、支付结果、延迟和错误。实际调用示例见测试目录。

T14 的订阅组合/套件、承诺期专用策略、Advanced Commerce、外部支付，以及 T15 的旧系统和其他平台尚未实现。促销签名、家庭共享、跨设备、商店账号切换、价格同意等真实商店行为仍需 Sandbox 验收。完整记录见 [实施与验收](StoreKitFlow-实施与验收记录.md)。

商品文案按用户确认沿用原版 `SubscriptionLocale` Swift 代码，支持原版 19 种语言。方法、示例及价格/优惠文案的原有边界见 [旧版多语言使用说明](StoreKitFlow-旧版多语言使用说明.md)。
