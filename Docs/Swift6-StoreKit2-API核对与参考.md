# StoreKit 2 API 核对与参考

核对日期：2026-11-05（Asia/Shanghai）。本页用于区分平台事实、当前实现和本项目拟定策略。

## 1. 核对环境和证据边界

- 本机工具链报告：Xcode 27.2（27B52）、Swift 6.4.2、iPhoneOS 27.2 SDK。
- 本机已检查 StoreKit.framework 的公开 `.swiftinterface`，用于核对符号、Sendable 和 availability。
- 官方资料通过 Apple Developer / Swift.org 获取；部分 Apple HTML 页面仅提供 JavaScript 外壳，补读官方 `.md` 内容。
- 旧 `Docs/Archive/StoreKitAPI分析文档.md` 中的源文件行号不是当前 SDK 的稳定 API 契约。
- 前一轮项目模拟器编译确认了旧示例与库接口不匹配；目前已重构，实际构建和本地交易验证结果见实施记录。没有进行真实 Sandbox 实测。
- Swift 6 language mode 不等于最低部署系统必须为 iOS 17；iOS 17 是本方案为 SwiftUI Observation 选择的产品支持基线。

## 2. 关键规则与官方依据

| 主题 | 已核对结论 | 来源 |
|---|---|---|
| 购买结果与监听 | 本机购买成功返回 purchase result；不能只等 updates | [Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates) |
| 完成交易 | 内容/服务交付后才 finish；unfinished 用于补处理 | [finish](https://developer.apple.com/documentation/storekit/transaction/finish%28%29)、[unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished) |
| 当前权益 | 有效自动续订及宽限期包含在当前权益内；消耗品不在内 | [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) |
| 订阅组 | 一个组可因家庭共享等出现多个状态，不能只取 first | [status(for:)](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status%28for%3A%29) |
| 退款请求 | success 表示 App Store 收到请求，不表示退款已经批准 | [RefundRequestStatus.success](https://developer.apple.com/documentation/storekit/transaction/refundrequeststatus/success) |
| 管理订阅 | 使用系统管理界面；客户端没有通用静默取消接口 | [AppStore](https://developer.apple.com/documentation/storekit/appstore) |
| 手动恢复 | sync 用于主动同步，可能需要身份验证 | [AppStore.sync](https://developer.apple.com/documentation/storekit/appstore/sync%28%29) |
| 账户关联 | 购买参数 appAccountToken 可在交易中返回 | [appAccountToken](https://developer.apple.com/documentation/storekit/product/purchaseoption/appaccounttoken%28_%3A%29) |
| 促销 | 资格判断、选择和签名都需要接入购买流程 | [促销实现](https://developer.apple.com/documentation/storekit/implementing-promotional-offers-in-your-app)、[购买选项](https://developer.apple.com/documentation/storekit/product/purchaseoption) |
| JWS 促销签名 | 新 SDK 提供 compactJWS 购买选项；签名密钥留在服务端 | [promotionalOffer](https://developer.apple.com/documentation/storekit/product/purchaseoption/promotionaloffer%28_%3Acompactjws%3A%29)、[生成 JWS](https://developer.apple.com/documentation/storekit/generating-jws-to-sign-app-store-requests) |
| 消耗品历史 | 系统有包含已完成消耗品历史的配置；不等于余额恢复 | [SKIncludeConsumableInAppPurchaseHistory](https://developer.apple.com/documentation/bundleresources/information-property-list/skincludeconsumableinapppurchasehistory) |
| 本地/沙盒测试 | 两种测试环境有不同边界，均需对应验证 | [测试阶段](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox) |
| Swift 6 并发 | actor 隔离、Sendable 及迁移需要编译检查 | [Swift 6 迁移指南](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/)、[常见并发问题](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/) |
| 新产品类型 | 官方符号页和本机 SDK 明确 iOS 27+ 存在新类型 | [subscriptionBundle](https://developer.apple.com/documentation/storekit/product/producttype/subscriptionbundle)、[subscriptionSuite](https://developer.apple.com/documentation/storekit/product/producttype/subscriptionsuite) |

`Pro` 是应用业务定义，不是 Apple 返回的标准布尔属性。商品映射、权益等级、非续订累加、离线保留、消耗品退款补偿和账号归属均是本方案建议，需产品确认，不能引用 Apple 文档冒充系统默认行为。

## 3. 可用性与兼容策略

| 能力 | 本机 SDK 核对结果 / 计划 |
|---|---|
| 四类标准 Product、Transaction、currentEntitlements | StoreKit 2 基础能力；方案主线部署 iOS 17+ |
| `Product.SubscriptionInfo.Status.updates` | 本机公开接口提供；订阅状态监听优先使用该序列。它的完整性仍由当前查询和生命周期刷新补足 |
| `Product.SubscriptionInfo.Status.all` | 本机 SDK 标注 iOS 17+，可用于全组状态快照；不能代替交易交付处理 |
| 按组订阅管理界面 | iOS 17+；presentation 层显式传入 scene |
| `PurchaseIntent` | iOS 16.4+、macOS 14.4+；tvOS/watchOS/visionOS 标不可用；每平台单独守卫 |
| `Transaction.offer` | iOS 17.2+；iOS 17.0/17.1 使用兼容映射 |
| `winBackOffer` 和对应优惠能力 | iOS 18+；不可用系统不展示可购买的 win-back 选项 |
| `promotionalOffer(_:compactJWS:)` | 本机 SDK 支持并提供 back-deployment；返回购买选项数组，需要合并进 Set。编译 SDK 与运行系统可用性分别验证 |
| appTransactionID / 新交易和续订字段 | 部分带 back-deployment，部分需新运行系统；逐字段核对，不按一个全局版本简单假定 |
| 撤销类型、部分退款、承诺期字段 | 新系统增强；旧系统保留 unknown 原因，不猜测比例或退款类型 |
| `subscriptionBundle` / `subscriptionSuite` | iOS/macOS 等 27+；目前核对到符号，业务闭环尚需官方更完整说明和真实商品验证 |
| Advanced Commerce | 单独能力及资格要求；不等同于标准 Product 路径，列入条件任务 |

API 存在不意味着 App Store Connect 已配置或账号具备相应资格。实施 T01/T14 将产出可编译的 availability 检查和能力报告，不直接依据 SDK 字段数量宣称所有功能已完成。

## 4. 对历史说明的纠正

1. `Transaction.updates` 不是所有本机购买成功的唯一交付入口。
2. 订阅状态变化不能只靠轮询；可使用状态更新流，再用快照/前台刷新兜底。
3. “扣款重试仍可用”不能作为通用规则；应区分宽限权益和没有宽限权益的重试。
4. `RenewalInfo.renewalDate`、`gracePeriodExpirationDate` 与 `Transaction.expirationDate` 不可混为同一个字段。
5. 退款申请返回成功不等于用户已退款；关闭订阅管理界面不等于已经取消。
6. 交易 ID 去重只防重复交付；同交易的退款/撤销修订仍必须处理。
7. “所有回调在主线程”不自动意味着所有共享可变状态符合 Swift 6 数据隔离。
8. 已完成消耗品历史不能被用来重放发货；自有余额需要自己的账本。
9. 商品的优惠目录不是用户已获得资格的证明；也不意味着普通 purchase 会应用任意一个促销。
10. 验证 `VerificationResult` 是客户端可信判断的一部分；将交易转成普通字典不能替代服务端验签和归属校验。

## 5. 仍需在实施时明确的事项

- 用户的实际最低系统、是否需要 macOS UI 及其他平台、可用的最低 Xcode。
- 正式产品 ID、Pro 映射、订阅组/等级、非续订期限和累加规则。
- 是否有自有账号、订单后端、促销签名服务、退款余额补偿政策。
- 是否实际采用新版组合产品、承诺期或 Advanced Commerce；没有真实场景时不得默认开启。
- 哪些场景能在 StoreKitTest 自动化，哪些需 Sandbox/TestFlight；测试失败必须保留证据。
- 生产环境 Apple 延迟、离线退款和跨设备同步的可接受时间，不承诺客户端绝对实时一致。
