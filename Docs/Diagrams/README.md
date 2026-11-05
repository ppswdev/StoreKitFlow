# 方案图表

日期：2026-11-05。状态：已与 StoreKitFlow 2.0 业务流程对齐。

所有图的可编辑源保存在 [时序图与流程图](../Swift6-StoreKit2-时序图与流程图.md) 的 Mermaid 代码块中。以下 SVG 为对应导出，不是独立设计来源；修改 Mermaid 后应重新导出对应 SVG。

| 图 | 文件 |
|---|---|
| 架构 | [01-architecture.svg](01-architecture.svg) |
| 初始化与恢复 | [02-initialization.svg](02-initialization.svg) |
| 购买与交付 | [03-purchase.svg](03-purchase.svg) |
| 统一交易处理 | [04-transaction-processing.svg](04-transaction-processing.svg) |
| Pro 判定 | [05-pro-resolution.svg](05-pro-resolution.svg) |
| 取消与退款 | [06-cancellation-refund.svg](06-cancellation-refund.svg) |
| 订阅状态 | [07-subscription-state.svg](07-subscription-state.svg) |
| 用户恢复购买 | [08-restore.svg](08-restore.svg) |

验证：使用 Mermaid 11 和隔离的 headless Chrome 完成 8/8 语法解析及 SVG 渲染；购买和 Pro 两张图进行截图视觉检查。渲染工具只在临时目录使用，未添加项目运行依赖。
