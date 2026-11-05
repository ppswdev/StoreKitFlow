> 历史资料：仅适用于 StoreKit2Manager 1.x，不适用于 StoreKitFlow 2.0。当前 API 见 [接入与业务规则](../StoreKitFlow-接入与业务规则.md)。

# StoreKit 2 版本功能变化明细

本文档详细列出了 StoreKit 2 在不同 iOS 系统版本中的功能变化，包括新增功能、废弃功能和重要更新。

---

## iOS 15.0+ (StoreKit 2 基础版本)

### 🆕 新增功能

#### 核心类型
- **Product** - 产品信息结构体
  - 支持所有产品类型（消耗品、非消耗品、非续订订阅、自动续订订阅）
  - 产品信息属性（id, displayName, description, price, displayPrice）
  - 订阅信息（SubscriptionInfo）

- **Transaction** - 交易信息结构体
  - 交易ID、产品ID、购买日期等基础属性
  - 交易验证机制（VerificationResult）
  - 交易完成方法（finish()）

- **AppStore** - App Store 交互枚举
  - `canMakePayments` - 检查支付能力
  - `deviceVerificationID` - 设备验证ID
  - `sync()` - 同步交易和续订信息

#### 订阅功能
- **Product.SubscriptionInfo** - 订阅信息
  - `introductoryOffer` - 介绍性优惠
  - `promotionalOffers` - 促销优惠列表
  - `subscriptionGroupID` - 订阅组ID
  - `subscriptionPeriod` - 订阅周期
  - `isEligibleForIntroOffer` - 检查介绍性优惠资格

- **Product.SubscriptionPeriod** - 订阅周期
  - 支持 day/week/month/year 单位
  - 周期值（value）

- **Product.SubscriptionOffer** - 订阅优惠
  - 优惠类型（introductory/promotional）
  - 支付模式（freeTrial/payAsYouGo/payUpFront）
  - 优惠价格和周期

#### 交易管理
- **Transaction.all** - 所有历史交易
- **Transaction.currentEntitlements** - 当前授权交易
- **Transaction.updates** - 实时交易更新监听
- **Transaction.latest(for:)** - 获取产品最新交易

#### 订阅状态
- **Product.SubscriptionInfo.Status** - 订阅状态
- **Product.SubscriptionInfo.RenewalState** - 续订状态
  - `.subscribed` - 已订阅
  - `.expired` - 已过期
  - `.inBillingRetryPeriod` - 计费重试期
  - `.inGracePeriod` - 宽限期
  - `.revoked` - 已撤销

- **Product.SubscriptionInfo.RenewalInfo** - 续订信息
  - `willAutoRenew` - 是否自动续订
  - `expirationDate` - 过期日期
  - `renewalDate` - 续订日期

#### 交易属性
- **Transaction.OfferType** - 优惠类型
  - `.introductory` - 介绍性优惠
  - `.promotional` - 促销优惠
  - `.code` - 代码优惠

- **Transaction.OwnershipType** - 所有权类型
  - `.purchased` - 用户购买
  - `.familyShared` - 家庭共享

- **Transaction.RevocationReason** - 撤销原因
  - `.developerIssue` - 开发者问题
  - `.other` - 其他原因

---

## iOS 15.4+

### 🆕 新增功能

- **Product.ProductType.localizedDescription** - 产品类型的本地化描述

---

## iOS 16.0+

### 🆕 新增功能

#### AppStore 扩展
- **AppStore.Environment** - 服务器环境枚举
  - `.production` - 生产环境
  - `.sandbox` - 沙盒环境
  - `.xcode` - Xcode 测试环境

#### 订阅管理界面
- **AppStore.showManageSubscriptions(in:)** - 显示订阅管理界面
  - 支持在 UIWindowScene 中显示
  - 用户可以在应用内管理订阅

#### 优惠代码兑换
- **AppStore.presentOfferCodeRedeemSheet(in:)** - 显示优惠代码兑换界面
  - 支持兑换订阅优惠代码
  - 交易会通过 `Transaction.updates` 发出

#### 应用评价
- **AppStore.requestReview(in:)** - 请求应用评价
  - 在 UIWindowScene 中显示评价请求

#### 消息系统
- **Message** - App Store 消息结构体
  - `display(in:)` - 显示消息
  - `messages` - 待显示消息的异步序列
  - 用于显示来自 App Store 的重要消息

#### AppTransaction
- **AppTransaction** - 应用交易信息
  - `appID` - 应用ID
  - `appTransactionID` - 应用交易ID
  - `appVersion` - 应用版本
  - `bundleID` - Bundle ID
  - `environment` - 环境信息
  - `originalAppVersion` - 原始应用版本
  - `originalPurchaseDate` - 原始购买日期
  - `deviceVerification` - 设备验证数据
  - `shared` - 获取缓存的或从服务器获取的 AppTransaction
  - `refresh()` - 刷新 AppTransaction

#### 订阅周期格式化
- **Product.SubscriptionPeriod.dateRange(referenceDate:)** - 获取订阅周期的日期范围
- **Product.SubscriptionPeriod.formatted(_:referenceDate:)** - 格式化订阅周期

---

## iOS 16.4+

### 🆕 新增功能

#### 产品推广
- **Product.PromotionInfo** - 产品推广信息
  - `productID` - 产品ID
  - `visibility` - 可见性状态
  - `update()` - 更新推广信息
  - `currentOrder` - 当前推广顺序
  - `updateProductOrder(byID:)` - 更新产品顺序
  - `updateProductVisibility(_:for:)` - 更新产品可见性
  - `updateAll(_:)` - 批量更新推广信息

- **Product.PromotionInfo.Visibility** - 可见性枚举
  - `.appStoreConnectDefault` - App Store Connect 默认值
  - `.visible` - 可见
  - `.hidden` - 隐藏

#### 订阅周期静态属性
- **Product.SubscriptionPeriod** 新增便捷静态属性：
  - `.weekly` - 一周
  - `.monthly` - 一个月
  - `.yearly` - 一年
  - `.everyThreeDays` - 每三天
  - `.everyTwoWeeks` - 每两周
  - `.everyTwoMonths` - 每两个月
  - `.everyThreeMonths` - 每三个月
  - `.everySixMonths` - 每六个月

#### 支付方式绑定
- **PaymentMethodBinding** - 支付方式绑定
  - `init(id:)` - 初始化并检查绑定资格
  - `bind()` - 绑定第三方支付方式到 App Store 账户
  - 支持绑定第三方支付方式（如支付宝、微信支付等）

- **PaymentMethodBinding.PaymentMethodBindingError** - 绑定错误
  - `.notEligible` - 不符合条件
  - `.invalidPinningID` - 无效的绑定ID
  - `.failed` - 绑定失败

---

## iOS 17.0+

### 🆕 新增功能

#### 订阅管理增强
- **AppStore.showManageSubscriptions(in:subscriptionGroupID:)** - 显示特定订阅组的管理界面
  - 可以指定订阅组ID，只显示该组的订阅

#### 交易原因
- **Transaction.Reason** - 交易原因枚举
  - `.purchase` - 购买
  - `.renewal` - 续订
  - 用于区分交易是首次购买还是订阅续订

---

## iOS 17.2+

### 🆕 新增功能

#### 交易优惠详情
- **Transaction.Offer** - 交易优惠详情结构体
  - `id` - 优惠ID
  - `type` - 优惠类型
  - `paymentMode` - 支付模式
  - 提供更详细的优惠信息

### ⚠️ 废弃功能

- **Transaction.offerType** - 废弃，使用 `Transaction.offer.type` 替代
- **Transaction.offerID** - 废弃，使用 `Transaction.offer.id` 替代
- **Transaction.offerPaymentModeStringRepresentation** - 废弃，使用 `Transaction.offer.paymentMode.rawValue` 替代
- **Transaction.offerPeriodStringRepresentation** - 废弃，使用 `Transaction.offer.period` 替代（iOS 18.4+）

---

## iOS 18.0+

### 🆕 新增功能

#### 赢回优惠
- **Product.SubscriptionInfo.winBackOffers** - 赢回优惠列表
  - 用于重新吸引已取消订阅的用户
  - 返回配置的赢回优惠数组

- **Product.SubscriptionOffer.OfferType.winBack** - 赢回优惠类型
  - 新增优惠类型，用于赢回优惠

- **Transaction.OfferType.winBack** - 交易中的赢回优惠类型
  - 支持在交易中识别赢回优惠

---

## iOS 18.4+

### 🆕 新增功能

#### 高级商务 API
- **AdvancedCommerceProduct** - 高级商务产品
  - `id` - 产品标识符
  - `type` - 产品类型
  - `purchase(compactJWS:confirmIn:options:)` - 使用 JWS 格式购买
  - `latestTransaction` - 最新交易
  - `allTransactions` - 所有交易
  - `currentEntitlements` - 当前授权
  - 支持更灵活的购买流程和自定义选项

- **AdvancedCommerceProduct.PurchaseOption** - 购买选项
  - `onStorefrontChange(shouldContinuePurchase:)` - 商店区域变化时的处理

#### 平台信息
- **AppStore.Platform** - 平台类型枚举
  - `.iOS` - iOS 平台
  - `.macOS` - macOS 平台
  - `.tvOS` - tvOS 平台
  - `.visionOS` - visionOS 平台

- **AppTransaction.originalPlatform** - 原始购买平台
  - 替代 `originalPlatformStringRepresentation`
  - 提供类型安全的平台信息

#### 交易优惠周期
- **Transaction.Offer.period** - 优惠周期
  - 提供优惠的详细周期信息
  - 类型为 `Product.SubscriptionPeriod?`

### ⚠️ 废弃功能

- **AppTransaction.originalPlatformStringRepresentation** - 废弃，使用 `originalPlatform` 替代

---

## 版本兼容性总结

### 核心功能支持
| 功能 | iOS 15.0+ | iOS 16.0+ | iOS 16.4+ | iOS 17.0+ | iOS 17.2+ | iOS 18.0+ | iOS 18.4+ |
|------|-----------|-----------|-----------|-----------|-----------|-----------|-----------|
| 基础产品购买 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 订阅管理 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 交易监听 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 订阅管理界面 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 优惠代码兑换 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 产品推广 | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 支付方式绑定 | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 交易原因 | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| 交易优惠详情 | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 赢回优惠 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 高级商务API | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 订阅功能支持
| 功能 | iOS 15.0+ | iOS 16.0+ | iOS 16.4+ | iOS 17.0+ | iOS 17.2+ | iOS 18.0+ | iOS 18.4+ |
|------|-----------|-----------|-----------|-----------|-----------|-----------|-----------|
| 介绍性优惠 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 促销优惠 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 赢回优惠 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 订阅状态监听 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 订阅管理界面 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 迁移建议

### 从 iOS 15.0 迁移到 iOS 16.0+
- 使用 `AppStore.showManageSubscriptions(in:)` 替代自定义订阅管理
- 使用 `AppStore.presentOfferCodeRedeemSheet(in:)` 支持优惠代码兑换
- 使用 `AppTransaction.shared` 获取应用交易信息

### 从 iOS 16.0 迁移到 iOS 17.2+
- 使用 `Transaction.offer` 替代废弃的 `offerType`、`offerID` 等属性
- 使用 `Transaction.Reason` 区分购买和续订

### 从 iOS 17.2 迁移到 iOS 18.0+
- 支持赢回优惠功能，用于重新吸引已取消订阅的用户

### 从 iOS 18.0 迁移到 iOS 18.4+
- 使用 `AppTransaction.originalPlatform` 替代 `originalPlatformStringRepresentation`
- 考虑使用 `AdvancedCommerceProduct` 进行更灵活的购买流程

---

## 重要注意事项

### 1. 版本检查
在使用新功能前，务必检查系统版本：
```swift
if #available(iOS 18.0, *) {
    // 使用赢回优惠
}
```

### 2. 向后兼容
- 所有基础功能在 iOS 15.0+ 都可用
- 新功能都有版本检查，不会影响旧版本
- 废弃的 API 会在多个版本后移除，有足够时间迁移

### 3. 测试建议
- 在不同 iOS 版本上测试应用
- 使用 Xcode 的 StoreKit Testing 进行测试
- 在沙盒环境中测试所有购买流程

### 4. 错误处理
- 始终处理可能的错误情况
- 使用 `VerificationResult` 验证交易
- 妥善处理网络错误和系统错误

---

## 参考资源

- [Apple StoreKit 2 文档](https://developer.apple.com/documentation/storekit)
- [StoreKit 2 迁移指南](https://developer.apple.com/documentation/storekit/in-app_purchase/migrating_to_storekit_2)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)

---

**最后更新**: 2025年12月  
**基于**: StoreKit 2 API (iOS 15.0 - iOS 18.4+)

