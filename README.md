# StoreKitFlow

Swift 6 的 StoreKit 2 封装与 SwiftUI 示例。公开入口为 `StoreClient`；这是从 StoreKit2Manager 到 **2.0 的 API 重构，当前尚未发布**。

支持 iOS / iPadOS 17+；macOS 14+ 支持核心查询、购买、权益和账本，示例及 Scene 系统界面适配为 iOS。已验证工具链为 **Xcode 27.2 / Swift 6.4.2**；使用 Swift 6 language mode，不承诺所有旧版 Swift 6 SDK 均可编译。

## 功能

- 四类标准内购：消耗品、非消耗品、自动续订、非续订订阅。
- 商品目录、缺失 ID、价格与所有可获取的原始商品信息；介绍性、促销、召回优惠和资格。
- 统一处理购买结果、交易监听、未完成交易、恢复和原生 StoreKit View 回调。
- 持久化交付账本、同交易并发去重、交付后 finish、有限自动重试和手动补单。
- `ProStatus` 包含 unknown / inactive / active、权益来源、有效期和待核实标记。
- 自动续订状态、宽限期、纯扣款重试、退款/家庭共享撤销、升级及多来源聚合。
- iOS 当前 Scene 的购买、管理订阅、退款申请和优惠码入口。
- Observation 快照与独立 `AsyncStream` 事件订阅；离线 Preview Gateway。
- 沿用原版 `SubscriptionLocale` Swift 代码提供 19 种语言文案；使用边界见 [旧版多语言说明](Docs/StoreKitFlow-旧版多语言使用说明.md)。
- 默认不需要自有账号或后端；可选注入验证、交付与优惠签名服务。

## 运行示例

打开 `StoreKitFlow.xcworkspace`，选择 **StoreKitFlowExample** 和 iOS 模拟器运行。Run 配置使用 `Example/StoreProducts.storekit`，这是本地模拟交易。Test 使用 `StoreKitFlow.xctestplan`。

真机运行需选择自己的开发团队、唯一 bundle ID。接入真实商店时，替换 `Example/StoreKitFlowApp.swift` 的商品 ID、配置自己的 App Store Connect 商品，并关闭 Run 中的本地 StoreKit 配置。

在另一台电脑运行源码不会自动把你的开发者账号绑定到原作者。Git 远端、示例 bundle/product ID 与 Apple 账号不是一回事；真实内购归属仍由实际 App、商品配置、签名和商店账号决定。

## SPM 接入

当前可以通过 Xcode 的 **Add Local Package** 选择本目录，添加产品 `StoreKitFlow`。发布 2.0 tag 后才能按对应版本从远端添加；本文不提供尚未存在的已发布版本承诺。

```swift
import StoreKitFlow

let configuration = StoreConfiguration(products: [
    .init("your.app.pro.monthly", kind: .autoRenewable, entitlements: ["pro"]),
    .init("your.app.pro.lifetime", kind: .nonConsumable, entitlements: ["pro"]),
    .init("your.app.pass.month", kind: .nonRenewable,
          entitlements: ["pro"], term: Term(1, .month)),
    .init("your.app.credits.10", kind: .consumable, credits: 10)
])
// 在 MainActor / SwiftUI App 根部持有一个实例。
let store = StoreClient(configuration: configuration)
try await store.start()
```

iOS 购买前传入发起操作的活跃 `UIWindowScene`，详见示例 `SceneReader`：

```swift
store.setPurchaseScene(scene)
let result = try await store.purchase(productID: "your.app.pro.monthly")
// 用 store.proStatus / store.snapshot 驱动 UI，不自行赋值 isPro。
```

完整接入、结果处理、扩展契约和业务边界见 [接入与业务规则](Docs/StoreKitFlow-接入与业务规则.md)。

## 验证

```sh
swift test
xcodebuild -workspace StoreKitFlow.xcworkspace -scheme StoreKitFlowExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

请替换为本机实际可用的模拟器。具体通过情况、待真实环境验证项和复现命令见 [实施与验收记录](Docs/StoreKitFlow-实施与验收记录.md)。

## 文档与发布

[文档导航](Docs/README.md) · [已确认决策](Docs/StoreKitFlow-决策记录.md) · [时序图与流程图](Docs/Swift6-StoreKit2-时序图与流程图.md) · [任务与验收矩阵](Docs/Swift6-StoreKit2-任务拆分与验收.md)

本地模块、工程和 podspec 已使用 StoreKitFlow；远端仓库 URL 暂仍为 `ppswdev/StoreKit2Manager`。仓库改名、SPM 模块改名、CocoaPods 名称变更是三件独立的事。保留旧 tag 可供旧用户继续依赖；新版本 `import StoreKitFlow` 属于破坏性变更，应以 2.0 发布。旧版本不能原地改 tag。无需为此次重构修改已有生产商品 ID。

`upgrade_ver.sh` 仅准备本地版本并验证，不会自动提交、打 tag、推送或发布。CocoaPods 的 `StoreKitFlow.podspec` 是新名称的发布准备文件；尚未发布到 trunk。

MIT License.
