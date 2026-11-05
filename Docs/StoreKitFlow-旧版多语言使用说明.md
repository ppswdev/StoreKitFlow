# 原版代码多语言使用说明

按用户确认，StoreKitFlow 恢复原版 `SubscriptionLocale` 的 Swift 代码、19 种语言文案和方法行为。没有新增 String Catalog 或资源包，也没有恢复旧版整个 StoreKit2Manager 管理器。

语言代码沿用原实现：`ar`、`de`、`en`、`es`、`fil`、`fr`、`id`、`it`、`ja`、`ko`、`pl`、`pt`、`ru`、`th`、`tr`、`uk`、`vi`、`zh_Hans`、`zh_Hant`。不匹配的代码按原实现回退英文；`zh-CN`、`zh-Hant` 等不会自动转换为旧代码，调用者需自行转换。

## 调用方式

```swift
import StoreKitFlow

let title = SubscriptionLocale.subscriptionTitle(
    periodType: .month, languageCode: "zh_Hans"
)
let shortTitle = SubscriptionLocale.subscriptionTitle(
    periodType: .year, languageCode: "en", isShort: true
)
let button = SubscriptionLocale.subscriptionButtonText(
    type: .freeTrial, languageCode: "zh_Hans"
)
```

`SubscriptionPeriodType` 提供 `week`、`month`、`year`、`lifetime`；`SubscriptionButtonType` 提供 `standard`、`freeTrial`、`payUpFront`、`payAsYouGo`、`lifetime`。

旧方法 `getUnit(from:)`、`getCurrencySymbol(from:)`、`defaultSubtitle(product:periodType:languageCode:)`、`introductoryOfferSubtitle(product:languageCode:)` 和 `promotionalOfferSubtitle(product:languageCode:)` 也已恢复。它们需要 Apple 的 `StoreKit.Product`，可从 `try await store.storeKitProduct(for: productID)` 获取；`ProductDetails` 是另一种 DTO。

示例商品详情里的“原版多语言文案”提供简体、繁体、英语和德语切换，展示旧标题和按钮用法；库仍支持以上全部 19 种原版语言。主购买按钮继续使用 StoreKit 商品信息，不使用旧优惠副标题决定购买。

## 沿用原实现的边界

为保持原版行为，原文案逻辑没有重写：

- 周期单位可能把 30 天、4 周等折算为月；旧标题枚举也不能表达“每 3 个月”。`getUnit(from: nil)` 会返回 `day`。
- 旧价格副标题将价格转为 Double 并固定两位小数，从价格字符串提取货币符号；部分货币、地区格式可能不正确，中文字符串还可能多带“元”。
- 介绍性优惠文案方法本身不核查试用资格；促销方法读取第一个优惠，未必等于购买时选择的优惠。不能仅凭其返回值承诺试用或实际成交价格。
- 原有语言复数和翻译尚未逐一由母语人士校对。测试覆盖旧接口、语言存在性及部分预期文案，并不证明所有翻译准确。

因此，实际价格优先显示 `ProductDetails.displayPrice`，周期使用 `periodValue`/`periodUnit`，资格使用 `OfferDetails.eligibility`，购买传入与展示一致的 `OfferSelection`。系统确认页和 StoreKit 实际交易结果为准。原版文案不会改变 `proStatus` 或自行发起购买。

原增强构想保留在 [历史补充方案](StoreKitFlow-本地化增强方案.md)，但本轮按用户选择使用旧实现，未实施其中的文案重写方案。
