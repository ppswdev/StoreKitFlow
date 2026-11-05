# Swift 6 API 与状态设计

> 已确认方案的原始设计草案；概念模块可能合并实现，下面的伪代码不作为最终签名。当前可调用 API 见 [接入与业务规则](StoreKitFlow-接入与业务规则.md)。主方案见 [优化方案](Swift6-StoreKit2-优化方案.md)。

## 1. 配置和初始化

`StoreConfiguration: Sendable` 通过值类型配置，不靠可随意修改的全局单例。

| 配置 | 说明 |
|---|---|
| `products: [ProductDefinition]` | 产品 ID、预期类型、展示顺序、所属订阅组、授予权益集合 |
| `entitlementRules` | `pro` 等权益 ID、等级关系、家庭共享接受策略 |
| `nonRenewingPolicies` | 每个非续订产品的时长、起算点、累加方式、规则版本 |
| `deliveryPolicies` | 每商品交付器；消耗品必须有持久化交付策略，不默认忽略 |
| `accountMode` | Apple 购买权益模式，或自有账户严格绑定模式 |
| `retryPolicy` | 仅后台查询/交付重试；退避、抖动、次数、可恢复错误分类 |
| `logging` | 等级、脱敏、诊断开关；默认不输出完整 JWS、token、设备验证数据 |
| `storage` | 账本位置、schema version、恢复/迁移方案；测试环境独立存储 |

开始前验证：重复/空 ID、未知权益、无时长非续订、消耗品无交付器、重复等级、商品类型与配置冲突。配置错误不进入支付流程。

初始化顺序：注册观察者 → 创建唯一任务集合 → 读取持久化记录 → 并行加载商品和权益 → 补单 → 合并初始快照。商品加载失败不阻断已购权益查询；初始化完成不保证所有未完成订单均已交付，应提供 `recoveringTransactions` 子状态。

同一配置的并发 `start()` 共用一个任务；`stop()` 幂等。禁止在 SwiftUI 每次 `body` 重算时重建管理器。重配先终结旧观察订阅并建立新 generation。

## 2. 主入口 API 草案

```swift
// 接口形状示意；DTO、错误与平台参数由后续实现任务定义。
@MainActor @Observable
public final class StoreKitClient {
    public private(set) var snapshot: StoreSnapshot
    public var proStatus: ProStatus { snapshot.entitlements.pro }
    public var isPro: Bool { proStatus.access == .active }

    public func start() async throws -> StartupReport
    public func stop() async
    public func refreshProducts(policy: RefreshPolicy) async throws -> ProductLoadReport
    public func productDetails(for id: ProductID,
                               refresh: RefreshPolicy) async throws -> ProductDetails
    public func refreshEntitlements(reason: RefreshReason) async -> RefreshReport
    public func purchase(_ request: PurchaseRequest) async throws -> PurchaseOutcome
    public func restorePurchases() async throws -> RestoreReport
    public func transactionHistory(_ query: HistoryQuery) async throws -> HistoryPage
    public func retryDelivery(for id: TransactionKey) async throws -> DeliveryReport
    public func events() -> AsyncStream<StoreEvent>
}
```

`StorePresentation` 单独提供 `manageSubscriptions(groupID:context:)`、`requestRefund(transactionID:context:)`、`redeemOfferCode(context:)` 和评分入口。传入调用页面对应的活跃 scene / window；不能从 `connectedScenes.first` 猜测当前窗口。未支持的平台显式返回 capabilityUnavailable，不伪装已成功显示。

如需暴露原生 `Product`，提供明确的 escape hatch，并声明调用方必须把直接购买结果交回 `processExternalPurchaseResult`。包括 `SubscriptionStoreView` 的成功回调也接入同一处理器，防止调用方绕过交付和去重。

## 3. 商品列表与详情完整度

`ProductLoadReport` 返回 `requestedIDs`、`loadedProducts`、`missingIDs`、`configurationMismatches`、`fetchedAt`、`storefront`、`freshness`。StoreKit 返回部分商品时不是整个请求失败；列出缺失商品，不猜测它一定未审核或不存在。

默认使用配置顺序；可选按原始 `Decimal` 价格排序。同价保持稳定顺序，不按格式化字符串排序。Storefront 变化使价格与优惠缓存失效；下一次购买前确认展示的仍是当前商店信息。

### 3.1 `ProductDetails`

| 数据域 | 应提供的数据 |
|---|---|
| 基础 | ID、原始类型与已知类型、名称、描述、家庭共享能力 |
| 价格 | Decimal 精确价格、displayPrice、货币代码、价格格式信息 |
| 订阅 | 订阅组 ID、组显示名/层级（SDK 可用时）、周期单位和值 |
| 优惠目录 | 全部介绍性/促销/win-back 优惠、ID、类型、金额、displayPrice、period、periodCount、paymentMode |
| 优惠资格 | eligible / ineligible / unknown / requiresServerDecision；每项来源与评估时间 |
| 当前状态 | 同组所有相关状态、对应交易、续订信息、验证质量；不伪装成商品静态属性 |
| 购买能力 | canMakePayments、运行系统限制、商品配置状态、当前操作冲突 |
| 扩展 | 能力集合、缺失原因、版本化 raw JSON，供调试和新字段前向兼容 |

“所有信息”是当前 SDK 和商店实际提供的信息的完整映射，不意味着能从 Product 读到 App Store Connect 内部审核数据、支付卡号、用户 Apple ID、所有退款审理细节或未来字段。

缺失字段用 Optional 或 `Availability<Value>` 表示 `.available` / `.notProvided` / `.unsupportedOS` / `.failed`，不能统一填 0、空字符串或 false。详情将静态商品数据与用户相关状态分开，避免每次 JSON 编码偷偷发起网络查询。

### 3.2 交易与续订详情

`TransactionDetails` 包括：交易 ID、原始 ID、web order line ID、product / group / bundle ID、购买和原始购买时间、到期时间、数量、类型、所有权、升级标识、交易原因、环境、金额/币种、优惠、签名时间、撤销日期/原因、可用时的撤销类型/比例、appTransactionID、appAccountToken。

`RenewalDetails` 包括：原交易链、currentProductID、autoRenewPreference、willAutoRenew、expirationReason、priceIncreaseStatus、isInBillingRetry、gracePeriodExpirationDate、renewalDate、renewalPrice/币种、recentSubscriptionStartDate、续订优惠与 win-back 资格、环境和验证信息。承诺期/组合关系/Advanced Commerce 等新字段独立 capability，不能在旧系统编造默认值。

原始签名证据保留为专用 `SignedEvidence`（JWS / jsonRepresentation / verification metadata），供可选服务端使用；普通 UI JSON 默认不包含敏感证据。字典转换不等于服务端验签。

所有 ID 对外 JSON 使用字符串；Decimal 采用精确十进制字符串或明确的十进制编码协议，避免 Double 和大整数精度损失。数组转换保持输入顺序，日期统一 UTC ISO-8601 或约定毫秒时间戳，带 schemaVersion。

## 4. 购买请求和结果

`PurchaseRequest` 包含 productID、合法 quantity、可选 appAccountToken、明确的 OfferSelection、operationID 和账号上下文。促销签名从 `OfferSigner` 获取；采用编译 SDK 支持的 JWS 促销接口，旧签名仅作兼容适配。私钥不能嵌入 App。

`PurchaseOutcome` 设计为：

| 结果 | 含义 | UI 行为 |
|---|---|---|
| `completed(transaction, delivery, entitlementRevision)` | 已验证且交付确认 | 展示完成，权限读取对应快照 |
| `pending(productID, operationID)` | 等待批准/外部完成 | 结束全屏 loading，展示等待，不授予新权益 |
| `userCancelled` | 用户主动取消此次购买 | 安静结束，不视为扣款失败 |
| `processing(transactionKey, reason)` | 已收到验证通过的交易，但交付/归属尚未完成 | 明确“支付已确认，权益处理中”，不引导重复购买 |

配置、系统、网络、购买受限、签名失败、未验证交易等通过 `StoreFailure` 抛出。已支付但交付失败不能伪装成普通“购买失败”，必须保留可恢复的订单状态和事件。

预检顺序：已启动 → 产品可用 → 配置匹配 → 账号策略 → canMakePayments → 当前系统支付界面互斥 → 优惠/数量 → 调用系统购买。对已拥有永久商品提供说明和恢复入口；同组订阅切换交给 Apple，不自行模拟扣款或比例退款。

数量仅用于系统支持的商品；非消耗品和订阅不接受任意数量。重复点击合并或返回 operationInProgress。pending 产品持久化提示避免误导重复支付，其他商品可继续操作。

不为无回执的 pending 自造交易 ID；Ask to Buy 拒绝或用户从其他设备取消不保证会发送一个明确失败事件，因此可以重新核对和清理过时提示，但不能宣称已收到 Apple 拒绝。

## 5. 状态快照与事件契约

### 5.1 快照分域

`StoreSnapshot` 包含 revision / generation / accountContext / lifecycle，以及：

- `catalog`: idle / loading / loaded / partial / failed；包含可保留的旧目录。
- `operations`: 按 operationID 的请求状态，不以一个全局 loading 覆盖所有业务。
- `entitlements`: 所有授权、Pro、评估原因、完整度和下一次刷新时间。
- `subscriptions`: 每组和每个交易链的当前状态、续订偏好、价格变化。
- `delivery`: 未完成交付、重试时间、需人工/用户处理原因。
- `diagnostics`: 最后一次查询错误、stale 信息、能力限制。

快照是 UI 的事实来源；事件用于提示、分析及业务协调。事件丢失后可用最新快照恢复，不能靠“收到一次 success 就永久设置 isPro”。

### 5.2 事件清单

| 类别 | 事件 |
|---|---|
| 生命周期 | started、initialReconciliationCompleted、stopped、contextChanged |
| 商品 | productsUpdated、productsPartiallyLoaded、storefrontChanged |
| 购买 | purchaseStarted、purchasePending、purchaseCancelled、purchaseCompleted、purchaseFailed |
| 交易交付 | transactionObserved、deliveryDeferred、deliveryCompleted、deliveryNeedsAttention、transactionFinished |
| 权益 | entitlementsChanged、proStatusChanged、verificationRequired |
| 订阅 | subscriptionStatusChanged、renewalPreferenceChanged、subscriptionPlanChangeScheduled、priceConsentRequired |
| 退款/撤销 | refundRequestSubmitted、refundRequestCancelled、entitlementRevoked、refundConfirmed（有明确退款证据时） |
| 恢复 | restoreStarted、restoreCompleted、restoreFailed |
| 诊断 | recoverableError、capabilityUnavailable、eventGapDetected |

每个事件包含 eventID、递增 sequence、generation、operationID（可选）、transactionKey（可选）、productID / groupID、timestamp、snapshotRevision、source。

事件语义约束：

1. 先提交状态和账本，再对外发“已交付/Pro 改变”；购买完成结果与事件携带同一 operationID，避免 UI 双重弹窗。
2. 新订阅者先读取当前快照，再读取其后的事件；需要原子订阅接口/游标，避免两者之间漏事件。
3. 每个 `events()` 订阅者拥有独立 continuation，广播而非共享一个迭代器抢事件。
4. 有界缓冲溢出必须暴露 gap 并要求重新读快照；事件流不承担发货或审计账本职责。
5. 主 UI 接口在 MainActor 更新；核心事件载荷 Sendable，取消订阅释放 continuation。
6. 跨重启交付保证依赖账本，不承诺业务回调 exactly-once。消费事件用于统计时也需 eventID 去重。
7. 初始状态快照可以表示已取消续订，但不把启动时观察到的状态变化伪装成“用户刚刚取消”的行为分析事件。

### 5.3 `StoreFailure`

包含类别、operation、productID、transactionKey、用户可读消息、诊断 code、底层 domain/code（脱敏）、retryability、suggestedAction。

至少区分：configuration、notStarted、productUnavailable、paymentsNotAllowed、operationInProgress、network、storeUnavailable、offerInvalid、offerIneligible、verificationFailed、accountConflict、deliveryFailed、persistenceFailed、presentationUnavailable、unsupportedCapability、unknown。

用户取消和 pending 属于正常结果，不强塞进 error；`CancellationError` 与用户取消 Apple 购买不是同一概念。未知枚举保留原始值，不崩溃、不自动授权。

## 6. 持久化与故障恢复

`DeliveryRecord` 至少记录：TransactionKey、证据摘要/必要签名证据、原交易链、产品、数量、owner context、policyVersion、处理阶段、attempts、nextRetryAt、交付收据、错误摘要、创建/更新时间。

阶段：observed → awaitingOwner / awaitingDelivery → delivered → finishRequested → finished。revoked / compensated 作为独立修订状态，不覆盖原购买审计信息。

| 中断点 | 重启行为 |
|---|---|
| 收到交易但尚未保存 | 从 unfinished/updates 重新处理 |
| 已保存但未交付 | 按原归属幂等交付 |
| 外部交付完成但本地未确认 | 以同一幂等键查交付结果，禁止盲目再发货 |
| 本地交付确认但未 finish | 只补 finish，不重复增加余额 |
| finish 已执行但本地阶段未更新 | 对账记录，允许重复 finish 的恢复路径，不重复交付 |
| 已交付后退款/共享撤销 | 按新证据修订重算或补偿，不因旧交易已处理而忽略 |
| 磁盘不可写/迁移失败 | 不 finish 未交付订单，发布需恢复状态 |

演示 App 使用事务型本地账本展示消耗品余额和去重。账本由应用支持目录保存、版本化迁移，环境隔离；卸载后本地余额不能承诺恢复。生产跨设备消耗品必须接入服务端账本。

退款补偿策略必须显式选择：仅收回未消费额度、允许负余额、记录债务或人工处理。部分退款以已验证的类型/比例及业务定义处理；资料不足时标记待核对，不能擅自扣全部余额。

## 7. SwiftUI 接入设计

应用根部创建 `@State` client 并注入 environment。根 `.task` 调用 start；scenePhase 进入 active 时触发去重刷新。根 task 消失不应不小心结束所有支付恢复任务，服务停止由应用级 owner 控制。

页面以 `proStatus.access` 分支：unknown 显示检查/重试；inactive 展示付费入口；active 解锁。附加 stale / needsPaymentUpdate / expiresAt 文案，不通过 `.onChange(isPro)` 负责发货。

演示页面至少包括：

1. 商品分类和详情：四种类型、所有优惠和可用性、价格及周期。
2. Pro 状态页：权益来源、有效期、宽限期、续订偏好、家庭共享、数据新鲜度。
3. 购买和恢复：pending、用户取消、受限、交付处理中、恢复空结果。
4. 订单与账本：当前权益、历史、最新交易、消耗品余额和补单状态。
5. 订阅管理和退款：明确区分请求结果与实际状态。
6. 调试场景：仅 DEBUG 显示可控时钟、Fake 失败、环境、事件时间线；正式包不显示敏感证据。

Preview 使用 FakeStoreKitGateway，不连接商店、不调用 sync、不触发购买。

## 8. 旧 API 迁移

| 原 API / 行为 | 新方案 |
|---|---|
| 强制 `shared.configure()` | 可注入实例 + 幂等 start；可选应用层 shared，库不强迫全局状态 |
| `isPurchased()` | `hasPurchaseHistory` 与 `hasEntitlement` 分开；Pro 使用 proStatus |
| 全局 `currentState` | 分域 snapshot + 类型化事件 |
| `purchase() -> Void` | `PurchaseOutcome` + 可解释错误 |
| `restorePurchases() throws` 但不抛错 | 真正可捕获失败 + RestoreReport |
| 全局非续订过期天数 | 每商品有效期策略 |
| 自动选择第一个促销优惠 | 明确 OfferSelection 与资格 |
| `[String: Any]` 为主 | Codable / Sendable DTO，必要时在边界提供兼容转换 |
| 查询历史时发退款业务事件 | 历史查询无副作用，退款由统一处理器处理 |
| Delegate / Closure 双路同时回调 | SwiftUI 快照 + 广播事件为主；兼容适配器明确互斥和线程语义 |

需兼容的旧接口只能转发新核心，不能维护第二套权益逻辑。无法保留语义的接口在 2.0 明确移除并给迁移示例。
