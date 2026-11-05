# Swift 6 StoreKit 2 时序图与流程图

> 与 StoreKitFlow 2.0 实现对齐的业务流程。交易处理器实际位于 StoreCoordinator 内，Scene 入口位于 StoreClient；图中的模块框表示职责。最终 API 见 [接入文档](StoreKitFlow-接入与业务规则.md)。

## 1. 模块架构

[查看 SVG](Diagrams/01-architecture.svg)

```mermaid
flowchart TD
    appRoot["SwiftUI App 根部"] --> client["StoreClient / MainActor Observable"]
    client --> coordinator["StoreCoordinator actor"]
    client --> presentation["StoreClient / 活跃 Scene"]
    presentation --> appleUI["Apple 购买、管理、退款界面"]
    coordinator --> gateway["AppleStoreGateway"]
    gateway --> appleStore["StoreKit 商品、交易、订阅状态"]
    coordinator --> processor["Coordinator.process"]
    processor --> ledger["DeliveryLedger / 持久化事务"]
    processor --> delivery["DeliveryHandler / 幂等交付"]
    delivery --> localBalance["本地余额或功能授权"]
    delivery -.-> backend["可选业务后端"]
    coordinator --> resolver["EntitlementResolver / 纯规则"]
    resolver --> snapshot["权益与 Pro 快照"]
    snapshot --> client
    coordinator --> events["带序号的广播事件"]
    events --> client
    backend -.-> serverAPI["App Store Server API / Notifications V2"]
```

核心不依赖 SwiftUI。图中后端为可选生产集成，领域测试使用 Fake 交付器验证契约，示例默认不访问业务后端。

## 2. 初始化与恢复时序

[查看 SVG](Diagrams/02-initialization.svg)

```mermaid
sequenceDiagram
    participant app as SwiftUI App
    participant ui as StoreClient
    participant core as StoreCoordinator
    participant sk as AppleStoreGateway
    participant db as DeliveryLedger
    participant rights as EntitlementResolver
    app->>ui: start()
    ui->>core: 校验配置并建立 generation
    core->>sk: 注册 Transaction.updates
    core->>sk: 注册 Subscription Status.updates
    core->>sk: 注册 Storefront 与可用 PurchaseIntent
    core->>db: 读取待交付记录和恢复上下文
    par 商品加载
        core->>sk: Product.products(for:)
        sk-->>core: 完整或部分商品 / 查询错误
    and 补单与权益加载
        core->>sk: Transaction.unfinished
        sk-->>core: 统一处理并确认交付
        core->>sk: currentEntitlements、历史与订阅组状态
        sk-->>core: 验证结果、完整度和当前状态
        core->>core: 恢复来源也经过交付确认
    end
    core->>rights: 已验证证据 + 配置 + 时间
    rights-->>core: Pro 和所有权益来源
    core-->>ui: 原子发布初始 snapshot revision
    ui-->>app: ready 快照和待交付记录
    loop 应用运行期间
        sk-->>core: 交易 / 状态 / 商店变化
        core->>core: 去重、合并刷新、重新计算
        core-->>ui: 新快照和有序事件
    end
```

监听先于扫描，来自扫描和监听的同一交易可能并发到达，必须合并。启动不调用 `AppStore.sync()`；商品目录失败不能阻断已有 Pro 的读取。

## 3. 购买与交付时序

[查看 SVG](Diagrams/03-purchase.svg)

```mermaid
sequenceDiagram
    participant user as 用户
    participant ui as SwiftUI 页面
    participant core as Coordinator
    participant sk as Apple StoreKit
    participant tx as Coordinator.process
    participant db as DeliveryLedger
    participant biz as DeliveryHandler
    user->>ui: 点击购买
    ui->>core: PurchaseRequest 和 operationID
    core->>core: 预检、互斥、商品和优惠确认
    core->>sk: 使用活跃 Scene 发起购买
    alt 用户取消
        sk-->>core: userCancelled
        core-->>ui: 正常取消，不改变已有 Pro
    else 等待批准
        sk-->>core: pending
        core-->>ui: 等待状态，结束阻塞式 loading
        sk-->>tx: 后续通过 updates 到达交易
    else 获得交易
        sk-->>core: success(VerificationResult)
        core->>tx: 统一处理交易
    end
    opt 本机结果或后续监听确实收到交易
    alt 验证失败或归属冲突
        tx-->>core: 不交付，不 finish，等待核实
        core-->>ui: 可解释的失败或处理中
    else 交易可处理
        tx->>db: 读取交易阶段并记录 observed
        alt 已确认交付
            db-->>tx: delivered 已确认
        else 尚未交付
            tx->>biz: deliver(transaction, idempotencyKey)
            biz-->>tx: 确认完成或抛出失败
            tx->>db: 成功时持久化 delivered
        end
        alt 交付未确认
            tx-->>core: processing / deliveryDeferred
            core-->>ui: 权益处理中，避免重复购买
        else 交付已确认
            tx->>sk: transaction.finish()
            tx->>db: 标记已完成或待对账
            tx->>core: 交付成功并请求权益重算
            core-->>ui: 对应 revision 快照和 completed
        end
    end
    end
```

图中 pending 后续处理是未来事件，不要求购买调用一直等待。用户取消分支无交易，不执行后续交付。外部服务交付和本地记录之间的中断，依靠相同幂等键恢复，不承诺分布式 exactly-once。

## 4. 统一交易处理流程

[查看 SVG](Diagrams/04-transaction-processing.svg)

```mermaid
flowchart TD
    incoming["购买结果 / updates / unfinished"] --> verify{"交易验证通过？"}
    verify -->|否| quarantine["隔离并报告，不发货，不 finish"]
    verify -->|是| context{"商品、环境、归属可确定？"}
    context -->|否| review["报告待核实，不 finish，保留 StoreKit 未完成交易"]
    context -->|是| mutation{"撤销或退款修订？"}
    mutation -->|是| revision["按证据版本去重，补偿并重算权益"]
    mutation -->|否| dedup["按交易键合并 in-flight 处理"]
    dedup --> delivered{"账本已确认交付？"}
    delivered -->|是| finish["补 finish，不重复发货"]
    delivered -->|否| save["持久化 observed"]
    save --> grant["使用幂等键交付"]
    grant --> confirmed{"交付和记录已确认？"}
    confirmed -->|否| retry["保存待重试状态，发布 processing"]
    retry --> later["下次启动 / 前台 / 有限退避重试"]
    later --> dedup
    confirmed -->|是| finish
    finish --> reconcile["对账，重算权益，发布快照与事件"]
    revision --> reconcile
```

持久化 observed 失败时直接进入待恢复错误，不继续交付。对于修订事件，是否需要完成对应 unfinished 交易由处理器检查；不能把退款修订当作新的正向发货。

## 5. Pro 判定流程

[查看 SVG](Diagrams/05-pro-resolution.svg)

```mermaid
flowchart TD
    beginEval["读取当前上下文、配置和时间"] --> evidence["当前权益 + 组状态 + 非续订记录"]
    evidence --> verifyData["验证并分离未知或无效证据"]
    verifyData --> perSource["逐个构造授权来源"]
    perSource --> mapped{"商品是否映射 Pro？"}
    mapped -->|否| otherRights["保留其他功能权益或消耗品账本"]
    mapped -->|是| type{"产品类型"}
    type -->|非消耗品| permanent["检查当前授权及撤销"]
    type -->|非续订| term["计算业务有效区间及撤销"]
    type -->|自动续订| sub{"已验证的当前状态"}
    type -->|未知或不支持| unresolved["不新增授权，报告能力限制"]
    sub -->|subscribed| active["有效来源，记录当前期限"]
    sub -->|inGracePeriod| grace["有效来源，使用宽限边界"]
    sub -->|expired / revoked / 无宽限的重试| invalid["该来源失效"]
    sub -->|资料不足| unresolved
    permanent --> union["合并所有有效来源和等级"]
    term --> union
    active --> union
    grace --> union
    invalid --> union
    unresolved --> union
    otherRights --> union
    union --> anyGrant{"至少一个有效 Pro 来源？"}
    anyGrant -->|是| pro["active，附来源、期限与新鲜度"]
    anyGrant -->|否| complete{"证据完整且可判定？"}
    complete -->|是| notPro["inactive，附明确原因"]
    complete -->|否| unknown["unknown，提示核实，不冒充未购买"]
    pro --> publish["原子发布快照，仅变化时发事件"]
    notPro --> publish
    unknown --> publish
```

`willAutoRenew=false` 不进入“该来源失效”分支。一个订阅退款也不能覆盖另一个有效的终身或家庭共享来源。恢复失败与完整扫描得到空结果必须区分。

## 6. 取消自动续订与退款时序

[查看 SVG](Diagrams/06-cancellation-refund.svg)

```mermaid
sequenceDiagram
    participant user as 用户
    participant app as App
    participant apple as Apple 系统界面
    participant stream as StoreKit 更新和状态查询
    participant core as 权益引擎
    alt 管理自动续订
        user->>app: 管理订阅
        app->>apple: showManageSubscriptions
        user->>apple: 选择取消或修改方案
        apple-->>app: 界面关闭
        app->>stream: 刷新订阅状态和当前权益
        stream-->>core: 当前状态与 willAutoRenew
        core-->>app: 到期前仍 active，更新续订偏好
        stream-->>core: 后续到期 / 新授权 / 状态变化
        core-->>app: 重新聚合全部 Pro 来源
    else 申请退款
        user->>app: 为指定交易申请退款
        app->>apple: beginRefundRequest
        apple-->>app: success / userCancelled / error
        app-->>user: 已提交申请或取消，不宣称退款完成
        stream-->>core: 后续撤销证据或有效权益变化
        core->>core: 去重修订、补偿、重算全部来源
        core-->>app: 真实权益结果和有依据的退款事件
    end
```

提交退款与审批结果之间没有固定完成时限；离线或 App 挂起时后续变化可能到下次刷新才观察到。没有足够原因信息时只能报告撤销，不能冒充知道退款审理结果。

## 7. 订阅状态与 Pro 的关系

[查看 SVG](Diagrams/07-subscription-state.svg)

```mermaid
stateDiagram-v2
    [*] --> Checking
    Checking --> Active: 已验证有效来源
    Checking --> Inactive: 完整证据无有效来源
    Checking --> Uncertain: 资料不足
    Active --> Active: 关闭自动续订但未到期
    Active --> Grace: 已验证宽限期
    Grace --> Active: 续费成功
    Active --> Inactive: 到期或撤销且无其他来源
    Grace --> Inactive: 宽限结束且无其他来源
    Inactive --> Active: 新购买或恢复有效来源
    Active --> Uncertain: 来源到期且无法核实后续状态
    Uncertain --> Active: 重新验证成功
    Uncertain --> Inactive: 完整证据确认失效
```

此图表示聚合后的访问状态示意，不是 Apple 枚举的一对一复制。Grace 提供访问权限；Inactive 可附 expired、revoked、billingRetry 等原因；多个来源并存时只有全部失效才关闭 Pro。

## 8. 用户恢复购买时序

[查看 SVG](Diagrams/08-restore.svg)

```mermaid
sequenceDiagram
    participant user as 用户
    participant ui as SwiftUI
    participant core as Coordinator
    participant sk as StoreKit
    participant proc as Coordinator.process
    user->>ui: 点击恢复购买
    ui->>core: restorePurchases()
    core-->>ui: restoreStarted
    core->>sk: AppStore.sync()
    alt 认证取消或同步错误
        sk-->>core: 抛出错误
        core-->>ui: restoreFailed，保留仍有效的已有权益
    else 同步完成
        sk-->>core: sync 完成
        core->>sk: 查询当前权益、组状态和未完成交易
        sk-->>proc: 未完成交易统一交付
        sk-->>core: 当前有效证据
        core->>core: 重算并删除已确认消失的旧来源
        core-->>ui: RestoreReport 与新快照
        ui-->>user: 已恢复 / 无可恢复权益 / 部分待处理
    end
```

恢复购买不重发已经消费的金币，不保证恢复另一个自有账户的订单；严格账号模式下必须先核实归属。
