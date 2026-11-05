# 商品与订阅文案本地化：旧方案增强版

日期：2026-11-05。状态：历史补充提案。用户随后选择保留原版 Swift 代码方案；当前实现见 [旧版多语言使用说明](StoreKitFlow-旧版多语言使用说明.md)。本页不将下述拟定 API 当作现有可调用接口。

## 1. 建议结论

保留旧版 `SubscriptionLocale` 的价值：内置多语言、一键生成标题/副标题/按钮、支持指定语言、提供优惠与续费说明。内部改为 **StoreKit 事实数据 + 独立文案规则 + 本地化资源 + App 覆盖**。

默认继续支持旧版 19 种语言，保留 `SubscriptionLocale` 作为便捷入口。调用者仍然拿到可直接显示的字符串，不必为每个 App 重写一套付费墙文案。新的完整结果使用结构化 `ProductPresentation`，避免标题、优惠说明和实际购买选择各自推断。

当前核心库已返回 StoreKit 的本地化名称、描述和价格，旧版自定义文案代码也已按用户确认恢复；本页的增强设计并未实施。

## 2. 旧代码中值得保留与需要修正的内容

已核对 Git 原版 `StoreKit2/StoreKit2Manager/Locals/SubscriptionLocale.swift`（约 1,300 行），不是仅凭文件名推测。

| 旧能力/实现 | 保留或调整 |
|---|---|
| 标题、短标题、副标题、按钮 | 保留，统一从一个 presentation 结果生成 |
| 19 种语言和 `languageCode` | 保留；补充规范化、地区/文字体系匹配和明确回退 |
| 大量语言 switch | 文案迁入 String Catalog，规则保留 Swift，便于翻译与复数管理 |
| 30 天当月、4 周当月、52 周当年 | 删除这种自动换单位；保留真实 value + unit |
| 3 个月商品按“每月价格”显示 | 明确“每 3 个月”，不丢周期数量 |
| 从 displayPrice 正则提取货币符号 | 不再解析价格字符串；直接使用原始 displayPrice |
| Decimal 转 Double、统一两位小数 | Decimal 计算，遵循对应货币与商店价格格式 |
| 中文模板统一追加“元” | 删除；中文 App 在美国商店仍显示美元 |
| 月价 ÷ 4.33、年价 ÷ 52 | 保留“折算价格”功能为可选；默认建议年价折算月价并标“约”和“按年扣费” |
| 年订阅一律写“最优惠” | 只有指定有效比较对象并完成可比性校验才显示节省比例；不默认声称最优惠 |
| `promotionalOffers.first` | 按用户选中的 offer ID 生成文案，并把同一选择传给购买 |
| 仅存在 intro offer 就生成试用承诺 | 必须结合资格；资格未知不写“立即免费试用” |
| `.payAsYouGo` 翻译成“按需付费” | 改为明确的“前 N 期每期优惠价”；它不是按使用量计费 |
| 多语言直接追加英文 s | 用完整句子的复数变体和参数顺序，处理阿拉伯语/斯拉夫语等规则 |

旧文件可作为翻译素材来源，但应校对错误，不把“旧版已经支持”当作语言质量已经验收。

## 3. 三类信息分别处理

### 3.1 商店提供的事实

原始 `displayName`、`description`、`displayPrice`、优惠 displayPrice、货币、周期及资格保留，不被文案层覆盖。直接展示价格使用 `displayPrice`；计算年均/月均等派生价格使用 Decimal 和 `product.priceFormatStyle`。这是 Apple 对直接价格与派生价格的区分。[displayPrice](https://developer.apple.com/documentation/storekit/product/displayprice)、[priceFormatStyle](https://developer.apple.com/documentation/storekit/product/priceformatstyle)

App 内切换语言不等于切换商店地区或货币，也不能向 `Product.products(for:)` 传入任意语言以保证商店名称随之切换。App 希望标题立刻随内部语言切换时，使用自己的本地化展示标题；原始商店字段继续保留。

### 3.2 库提供的通用业务文案

根据确切周期、类型、当前选择的优惠、资格和订阅快照生成：

- 标题/短标题：周订阅、月订阅、每 3 个月、年订阅、永久解锁、非续订通行证。
- 价格与结算周期：每月、每 3 个月、一次性购买。
- 优惠阶段：免费试用、前 N 期优惠价、前一段期间一次支付，及后续续费价格。
- 按钮：订阅、开始免费试用、购买、已拥有、等待批准、处理中。
- 订阅状态：将在某日续订、已关闭续订且有效至某日、宽限期、付款待处理、已到期。

“非消耗品”不能无条件命名“终身会员”；是否是 Pro 以及商业名称来自产品配置或 App 覆盖。消耗品单位如金币、次数、额度也由 App 提供，不能凭产品 ID 猜。

### 3.3 App 自定义文案

按 productID 和本地化 key 覆盖商业标题、卖点、角标及按钮语气，例如“专业版”“家庭方案”。默认回退至库模板，再回退至英语。

价格、计费周期、优惠资格等结构化事实仍单独输出。默认 UI 展示真实事实，宿主自定义文案不应隐藏或篡改这些信息。不采用产品 ID 后缀识别周/月/年。

## 4. 拟定接口与数据模型

以下是设计示例，并非当前代码：

```swift
let presentation = SubscriptionLocale.presentation(
    for: product,
    selection: selectedOffer,
    context: .init(
        locale: appLocale,
        subscription: subscriptionSnapshot,
        entitlements: entitlementSnapshot,
        productDefinition: definition
    ),
    options: .init(
        titleStyle: .generated,
        equivalentPrice: .monthlyForAnnual,
        overrides: appOverrides
    )
)
```

拟定 `ProductPresentation: Sendable` 输出：

| 字段 | 用途 |
|---|---|
| `title`, `shortTitle` | 保留旧版标题能力 |
| `subtitle`, `buttonTitle` | 可以直接用于 SwiftUI Text / Button |
| `priceText`, `billingPeriodText` | 主价格与真实扣费周期，独立于营销描述 |
| `offerText`, `renewalText` | 当前优惠阶段与优惠结束后的价格/周期 |
| `equivalentPriceText?` | 可选“约每月…”，始终标明实际按年扣费 |
| `statusText?`, `action` | 已购买/待批准/处理中，以及应购买、管理还是等待 |
| `selection`, `productID`, `catalogRevision` | 与下单参数关联，目录改变时重新生成 |
| `resolvedLanguage`, `issues` | 调试回退、未知周期、不可比较或资格不足 |

保留 `subscriptionTitle`、按钮等便捷函数的调用风格，由统一 formatter 实现；这不要求恢复整套旧管理器接口。价格符号提取等不安全旧函数不继续推广。

本地化层是纯渲染，不在转换字符串时偷偷请求订阅状态、不改变 Pro、不调用购买。业务错误按 StoreFailure.Code 映射用户文案，Apple 系统错误保留系统提供的本地化描述，原始 message 供诊断。StoreClient 负责加载事实，SwiftUI 负责传当前语言，formatter 负责生成文案。新增价格格式上下文时，从 StoreKit 的 formatter 获取 locale/currency，不解析 displayPrice。

## 5. 语言和资源策略

1. 继承旧版 19 种语言：ar、de、en、es、fil、fr、id、it、ja、ko、pl、pt、ru、th、tr、uk、vi、zh-Hans、zh-Hant。
2. 兼容旧 `zh_Hans` / `zh_Hant` 输入，内部使用标准语言标识。通过系统语言匹配处理地区和 script，不能简单 `split("-").first` 后丢掉简繁体。
3. 语言优先级：调用方显式设置 → SwiftUI 传入的 locale / App 选定语言 → 支持语言匹配 → 英语。货币不随这个回退链改变。
4. 用完整句子的 String Catalog 模板表达参数、复数和语序，避免把翻译过的单词拼接成句子。String Catalog 支持按语言提供 plural 变体。[Apple String Catalog 文档](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
5. App 可通过自己的 Bundle 和资源表覆盖。SPM 使用包资源 Bundle，CocoaPods 使用命名资源 bundle，不能默认所有字符串都在 Bundle.main。[Swift 包资源](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)
6. 资源分发同时验证 Xcode、命令行 `swift test` 和 CocoaPods。若某条构建链不能直接编译 xcstrings，则从同一 Catalog 在发布准备阶段生成标准 lproj / stringsdict 资源，不手工维护两份翻译。
7. App 内切换语言后重算 presentation；storefront/商品/优惠资格改变后也重算。缓存键包含相关目录版本、语言、选择和状态，不能只按 productID 缓存字符串。
8. 保留原语言覆盖，但需要按语言校对，特别是旧版俄语、波兰语、阿拉伯语的复数和中文计费措辞；自动测试通过不能代替母语文案校对。

## 6. 典型输出

以下为说明用的虚构价格，正式值来自 StoreKit：

| 场景 | 建议文案 |
|---|---|
| 普通月订阅 | “¥18.00 / 月” |
| 3 个月订阅 | “¥48.00 / 3 个月” |
| 年订阅 | “¥168.00 / 年” + 可选“约 ¥14.00 / 月，按年扣费” |
| 合格的 7 天试用 | “免费试用 7 天，之后 ¥18.00 / 月” |
| 试用资格未知 | 普通订阅文案；资格说明单独提示，按钮不承诺免费 |
| 前 3 个计费期按期优惠 | “前 3 个月每月 ¥6.00，之后每月 ¥18.00”（仅当优惠真实周期为 1 个月 × 3） |
| 6 个月预付优惠 | “前 6 个月一次支付 ¥60.00，之后每月 ¥18.00”（依据真实优惠总期限） |
| 有效期内关闭续订 | “已关闭自动续订，仍可使用至 2026年12月5日” |
| 中文 App、美元商店 | 中文句子 + Apple 返回的美元 displayPrice，不追加“元” |
| 一次性永久解锁 | “一次购买，永久解锁”；不写“自动续订” |
| 非续订月卡 | “一次购买，有效 1 个月，不自动续订” |

不能承诺确切“试用结束日”时使用周期说明；若展示日期，注明基于预计购买时间，购买后以已验证交易的实际到期日更新。

## 7. 折算价格和节省比例

保留旧版的价值对比功能，但作为明确可选项：

- 默认建议年价折算月价，展示“约”，主位始终显示实际扣费总价与周期。
- 按周折算保留开关，不默认把一年视为精确 52 周、一个月视为精确 4.33 周。若宿主启用近似周价，需选择并公开近似规则，不用于权益到期计算。
- 节省百分比需调用者明确提供比较商品；必须同货币、同权益且期限可比较。年价可与相同权益的 12 期月价比较。
- 预付 6 个月优惠不能与一个月标准价格直接比较。先确定覆盖期限，再计算可比较总价。
- 没有比较对象、比较不成立、价格非正或资格未知时不生成“节省 X%”“最优惠”。

## 8. 新增任务与验收

| 任务 | 交付 |
|---|---|
| L01 | 提取旧版 19 语言文本、规范 key、保留标题/副标题/按钮的便利入口 |
| L02 | ProductPresentation、语言上下文、事实/商业标题分离、App overrides |
| L03 | 精确周期、Decimal/StoreKit 价格格式、完整优惠阶段和未知资格降级 |
| L04 | String Catalog 复数/RTL、地区与简繁体匹配、SPM/Pods 资源 bundle |
| L05 | SwiftUI 示例语言切换、普通/试用/预付/续费/取消等文案预览 |
| L06 | 文案快照、占位符完整性、货币/周期/资格矩阵、分发构建和人工校对清单 |

必须覆盖：JPY 的零小数货币、KWD 等三位小数、阿拉伯数字和 RTL；3/6 个月、2 周和多个优惠期；资格 true/false/unknown；促销选中与实际参数一致；zh-CN/zh-TW/zh-HK 和旧下划线输入；应用语言改变但商店币种不变；按年扣费总价不会被均价遮蔽。

原提案推荐保留 19 种语言、使用 String Catalog 维护文案。该增强提案本轮未实施；用户已选择原版实现。
