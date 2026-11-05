# StoreKitFlow 2.0 实施与验收记录

实施与验证日期：2026-11-05 至 2026-11-06（Asia/Shanghai）。本记录描述该时段的本地验收结果，发布状态以 Git 标签和 CocoaPods trunk 的实际记录为准。

已按确认完成购买核心、SwiftUI 示例、分发准备和文档重构。用户随后确认保留原版 Swift 多语言方案，`SubscriptionLocale` 已恢复；见 [使用说明](StoreKitFlow-旧版多语言使用说明.md)。

## 1. 已交付内容

| 阶段 | 状态与具体交付 |
|---|---|
| T01 工程 | StoreKitFlow SPM 模块、Swift 6 language mode、iOS 17/macOS 14 支持声明、示例工程/workspace、宿主集成测试与 test plan |
| T02 模型 | Sendable DTO、三态权益、错误、快照、事件、Gateway；原始 JSON 与原生 Product 访问入口 |
| T03 权益 | 显式商品映射、有效期/宽限期、取消续订、纯重试期、撤销、家庭共享、升级、非续订期限和多来源并集 |
| T04 账本 | schema 1、原子持久化、发放去重、余额消费、部分退款补偿、损坏保护；不存在需要迁移的旧账本，未知 schema 明确失败 |
| T05 生命周期 | 合并启动、监听、定时/前台重算、generation、停止清理、广播和 revision |
| T06 交易 | purchase / updates / unfinished / 恢复统一处理；业务交付确认后 finish；pending、补单、有限退避和手动重试 |
| T07 目录 | 配置顺序、类型检查、缺失 ID、stale、storefront 变化、Decimal、原始 JSON；已恢复原版 19 语言 Swift 文案 |
| T08 系统入口 | iOS 活跃 Scene 的管理订阅、退款申请、优惠码、恢复；区分界面关闭/申请提交与实际权益结果 |
| T09 优惠 | 自动介绍性、指定促销签名、指定 win-back、购买意向保留优惠、原生购买结果接入；真实签名/资格仍待 Sandbox |
| T10 后端扩展 | 按最终确认只保留 TransactionValidator / DeliveryHandler / OfferSigner；无账号系统、无默认服务器请求，不实现 AccountPolicy 系统 |
| T11 示例 | 商品分类/详情、Pro、订阅状态、余额、历史/退款、管理/恢复、交付重试、意向、Debug 事件和离线预览 |
| T12 验证 | 领域自动化、本地 StoreKit 系统交易验证、示例构建；真实沙盒、最低 OS 运行和人工多语言/无障碍仍待验 |
| T13 分发/文档 | README、API/决策/验收、8 张时序/流程图、JSON 导出、podspec、仅本地操作的版本脚本；1.x 文档移到 Archive |
| T14/T15 | 条件任务尚未实施：SDK 27 组合/套件和 Advanced Commerce；其他平台与旧系统 |

实现把 TransactionProcessor 的职责合并在 StoreCoordinator，Scene 入口合并在 StoreClient。时间依赖是可注入的 Sendable 闭包。库默认没有日志输出，未增加一个无用途的日志框架。原 API 草案中的 AccountPolicy、多等级会员和完整服务器不是本轮最终确认范围。

## 2. 验证环境与结果

- Xcode 27.2（27B52），Swift 6.4.2；所有源码使用 Swift 6 language mode。
- Mac 核心测试：本机 macOS，部署目标 macOS 14。
- 系统集成：iPhone 17 模拟器 / iOS 27.2，StoreKit Xcode 本地环境，不使用真实扣款账号。
- `.storekit` 配置仅是演示商品，不能当作自己的 App Store Connect 商品。

| 检查 | 结果 |
|---|---|
| Swift Testing | **47 项通过**，部分测试含参数化场景；不是宣称原矩阵 63 项全部通过 |
| XCTest + StoreKitTest | **6 项通过**，全部由示例 App 承载并串行执行 |
| iOS 示例 | Swift 6 模拟器构建成功；实际通过本地 SPM 引用核心；离线预览主屏视觉检查通过 |
| CocoaPods | `pod lib lint` 完整 iOS + macOS 编译校验通过；不是只做 podspec 语法检查 |
| Mermaid | 8/8 语法与 SVG 渲染通过，初始化图另做视觉核对 |
| Git diff | 格式检查无空白错误；没有自动提交或发布 |

SDK 的 StoreKitTest Objective-C 头存在 SKPaymentTransactionState 弃用提示，AppIntents 元数据工具提示无相关框架而跳过；不属于项目的 Swift 6 并发错误。CocoaPods 不显式链接不存在的 Observation.framework，Swift 导入负责其运行库链接。

### 2.1 领域测试覆盖

配置去重；订阅六状态；自动续订开关；个人/共享/未知 ownership；共享禁用；升级替代；生命周期 unknown；完整空权益与不完整刷新；历史不直接授予订阅/消耗品 Pro；过期、缺失宽限边界；终身来源保留；非续订期限、叠加和退款；日历闰月；新签名不覆盖有效的续订状态判断。

账本原子写入和重新打开；重复交付；退款已消费差额；部分后全额退款；坏文件保护；环境隔离；余额不足不修改状态；20 个并发交易入口仅发放一次；交付过程中退款；交付失败不 finish/不授予 Pro；手动补单；已交付未 finish 重启补 finish；相同退款重新签名不重复业务补偿。

pending 跨 stop/start 保留；购买取消保留 Pro；启动不 sync；恢复错误/空恢复；目录失败不清权益；不同续费 ID 分别处理；缺失商品；非法 quantity；未启动预检；并发启动只监听/加载一次；购买互斥；停止后拒绝迟到权益；恢复来源也等待业务交付；独立事件消费者收到同一结果；JSON 大整数与 Decimal 无损、敏感证据不导出。

### 2.2 本地 StoreKit 集成测试

1. 四类标准商品加载和购买，消耗品 quantity=2、非续订解锁、永久来源、自动订阅来源。
2. Ask to Buy 返回 pending，不先解锁；批准后通过监听完成交付并清 pending。
3. 关闭自动续订后继续有效，再经加速自然到期变 inactive。
4. 原生 Product 购买结果回传同一流水线，重复回传不重复增加余额。
5. 消耗品退款后扣回本地可用余额。
6. 订阅退款只移除对应来源，终身 Pro 保持有效。

测试配置使用显式 StoreKit test plan 和 App 宿主。单独把 SKTestSession 放在没有 App 的 SPM xctest runner 中不作为有效集成环境。强制 expire 的试验曾在本机保持旧的 subscribed/到期数据；最终到期测试采用 Apple 支持的加速时间自然到期，不把模拟器内部状态当作生产逻辑修正依据。

## 3. 与原 63 场景矩阵的关系

以下说明已自动验证的边界，不替代逐项生产验收。

| 原场景组 | 本轮证据 | 仍需验证/额外条件 |
|---|---|---|
| C01–C08 目录 | 四类型真实本地目录、缺失 ID、失败保留、启动并发合并、Decimal 导出 | 真实 storefront 切换、各货币展示与完整语言/翻译质量需进一步验收 |
| P01–P12 购买 | 四类型、取消、Ask to Buy、pending 重启、互斥、原生回调、quantity | 系统支付限制、真实验证失败注入、签名优惠和 win-back 资格、跨窗口交互 |
| D01–D10 交付 | 并发去重、重启账本/补 finish、不同续费 ID、退款修订、坏文件 | 杀进程/磁盘满的故障注入、真实后端超时与对账；不能以 Fake 替代服务器验收 |
| E01–E15 权益 | 核心状态规则、取消到期、终身+退款、家庭 ownership、升级、非续订、空与不完整结果 | 真实宽限/扣款重试恢复、家庭共享并存/撤销、跨组切换、跨设备/重装与系统时间异常 |
| R01–R08 管理 | 恢复报告与错误、真实本地退款后权益变化、重复/部分退款规则 | 管理/申请退款/兑换的系统界面人工流程与真实审批；申请提交与批准不是同一测试 |
| A01–A10 架构 | start/stop、迟到响应、双消费者、并发退款、JSON、Swift 6 构建 | 慢消费者压力/真实账号切换、新 SDK 类型；自有账号 A02/A03 按确认延期 |

缺少证据的场景标为待验，不因存在对应代码就称作自动化通过。原版多语言已恢复；之前的 L01–L06 增强提案本轮未实施。

## 4. 生产接入前仍需做什么

1. 使用应用自己的 Team / bundle ID / 产品 ID，配置真实商品、订阅组、价格、优惠、家庭共享和宽限期。
2. 使用真实 Sandbox / TestFlight 验证介绍性资格、优惠码、促销签名、win-back、购买限制、支付中断、价格同意、升降级和跨设备恢复。
3. 管理订阅和退款申请在支持的真机系统上检查，确认前台 scene、取消结果和后续权益变化。
4. 安装最低支持的 iOS 17/macOS 14 与当前最新系统实测；本机结果不替代最低 OS 的运行验证。
5. 若业务需要跨设备消耗品余额、账号权益、防篡改账本或实时服务端通知，实施独立服务器集成；当前本地钱包不提供这些保证。
6. 对原版 19 语言文案进行翻译、复数、价格与无障碍校对。示例主要业务文字为中文，原版多语言标题和按钮有切换演示，商店字段由 StoreKit 本地化。

## 5. 复现命令与证据

在仓库根目录执行，模拟器名称/ID 替换为本机可用值：

```sh
swift test --scratch-path /private/tmp/StoreKitFlow-build

xcodebuild -workspace StoreKitFlow.xcworkspace -scheme StoreKitFlowExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/StoreKitFlow-integration \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test

pod lib lint StoreKitFlow.podspec --allow-warnings --skip-tests --platforms=ios,macos
```

本机日志位于 `/private/tmp/StoreKitFlow-build-final.log`、`/private/tmp/StoreKitFlow-reviewed.log`、`/private/tmp/StoreKitFlow-pod-final.log`。集成结果包为 `/private/tmp/StoreKitFlow-reviewed.xcresult`。这些是本机临时验证产物，不作为 SDK 资源分发。

发布前不要依赖临时目录长期保存证据，应在发布 PR 或 CI 中重新运行并保留产物。`upgrade_ver.sh` 不会替你提交、打 tag、推送或发布。

### 示例布局证据

[离线预览截图](Verification/Example-preview.png) 已视觉检查：标题、Pro、分组商品和价格可正常显示。截图明确标记模拟数据，用于布局检查，不作为真实商店价格或完整交互测试的证据。Debug 运行参数 `--preview` 可复现，Release 不启用该入口。
