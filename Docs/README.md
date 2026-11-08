# StoreKitFlow 文档

2026-11-05：方案已确认，已完成 2.0 购买核心的实现与本地验证。使用方式以当前 API 文档为准。

多语言采用用户确认的原版 Swift 代码方案，详见 [旧版多语言使用说明](StoreKitFlow-旧版多语言使用说明.md)；之前的 [增强提案](StoreKitFlow-本地化增强方案.md) 保留作历史参考。

1. [接入与业务规则](StoreKitFlow-接入与业务规则.md)：可调用 API、SwiftUI 接入、Pro、交付、恢复和可选后端。
2. [实施与验收记录](StoreKitFlow-实施与验收记录.md)：完成项、测试证据、环境限制和真实沙盒待验项。
3. [已确认决策](StoreKitFlow-决策记录.md)：命名、平台、无自有账号、Pro 与后端扩展边界。
4. [优化方案](Swift6-StoreKit2-优化方案.md)：原方案与范围依据。
5. [时序图与流程图](Swift6-StoreKit2-时序图与流程图.md)：8 张 Mermaid 图及 [SVG](Diagrams/README.md)。
6. [任务拆分与验收矩阵](Swift6-StoreKit2-任务拆分与验收.md)：63 个业务场景，不把场景数量当作已通过测试数量。
7. [API 核对与参考](Swift6-StoreKit2-API核对与参考.md)：Apple / Swift 官方来源与 SDK 可用性。
8. [原 API 设计草案](Swift6-StoreKit2-API与状态设计.md)：设计意图与概念模型；最终签名见接入文档和源码。
9. [SPM 发布教程](StoreKitFlow-SPM发布教程.md)：发布前检查、版本标签、推送和 Xcode 验证。

1.x 历史文档已移到 [Archive](Archive/README.md)，不作为新版本接入说明。
