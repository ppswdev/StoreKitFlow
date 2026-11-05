> 历史资料：仅适用于 StoreKit2Manager 1.x，不适用于 StoreKitFlow 2.0。当前 API 见 [接入与业务规则](../StoreKitFlow-接入与业务规则.md)。

# StoreKit 转换器使用指南

## 概述

转换器模块提供了将 StoreKit 2 的 Swift 对象转换为可序列化的基础数据类型（Dictionary/JSON）的功能，方便与其他语言（如 Flutter、React Native 等）进行数据交互。

## 转换器列表

### 1. ProductConverter
将 `Product` 对象转换为 Dictionary/JSON

### 2. TransactionConverter
将 `Transaction` 对象转换为 Dictionary/JSON

### 3. TransactionHistoryConverter
将 `TransactionHistory` 对象转换为 Dictionary/JSON

### 4. StoreKitStateConverter
将 `StoreKitState` 枚举转换为 Dictionary/JSON

### 5. SubscriptionConverter
将订阅相关对象（`SubscriptionInfo`、`RenewalInfo`、`RenewalState` 等）转换为 Dictionary/JSON

### 6. StoreKitConverter
统一转换接口，提供所有转换器的便捷方法

## 使用方法

### 统一接口（推荐）

使用 `StoreKitConverter` 提供的统一接口：

```swift
import StoreKit2Manager

// Product 转换
let productDict = StoreKitConverter.productToDictionary(product)
let productJSON = StoreKitConverter.productToJSONString(product)

// Transaction 转换
let transactionDict = StoreKitConverter.transactionToDictionary(transaction)
let transactionJSON = StoreKitConverter.transactionToJSONString(transaction)

// TransactionHistory 转换
let historyDict = StoreKitConverter.transactionHistoryToDictionary(history)
let historyJSON = StoreKitConverter.transactionHistoryToJSONString(history)

// StoreKitState 转换
let stateDict = StoreKitConverter.stateToDictionary(state)
let stateJSON = StoreKitConverter.stateToJSONString(state)

// RenewalInfo 转换
let renewalInfoDict = StoreKitConverter.renewalInfoToDictionary(renewalInfo)
let renewalInfoJSON = StoreKitConverter.renewalInfoToJSONString(renewalInfo)
```

### 单独使用转换器

```swift
// Product 转换
let productDict = ProductConverter.toDictionary(product)
let productsArray = ProductConverter.toDictionaryArray(products)
let productJSON = ProductConverter.toJSONString(product)

// Transaction 转换
let transactionDict = TransactionConverter.toDictionary(transaction)
let transactionsArray = TransactionConverter.toDictionaryArray(transactions)
let transactionJSON = TransactionConverter.toJSONString(transaction)
```

## 转换后的数据结构

### Product Dictionary

```json
{
  "id": "product_id",
  "displayName": "Product Name",
  "description": "Product Description",
  "price": 9.99,
  "displayPrice": "$9.99",
  "type": "autoRenewable",
  "subscription": {
    "subscriptionGroupID": "group_id",
    "subscriptionPeriod": {
      "value": 1,
      "unit": "month"
    },
    "introductoryOffer": {
      "id": null,
      "type": "introductory",
      "displayPrice": "Free",
      "price": 0.0,
      "paymentMode": "freeTrial",
      "period": {
        "value": 7,
        "unit": "day"
      },
      "periodCount": 1
    },
    "promotionalOffers": [],
    "winBackOffers": []
  }
}
```

### Transaction Dictionary

```json
{
  "id": "1234567890",
  "productID": "product_id",
  "purchaseDate": 1699123456789,
  "expirationDate": 1701715456789,
  "revocationDate": null,
  "isRefunded": false,
  "isRevoked": false,
  "productType": "autoRenewable",
  "ownershipType": "purchased",
  "originalPurchaseDate": 1699123456789,
  "environment": "production",
  "appAccountToken": null,
  "reason": "purchase"
}
```

### TransactionHistory Dictionary

```json
{
  "productId": "product_id",
  "transactionId": "1234567890",
  "purchaseDate": 1699123456789,
  "expirationDate": 1701715456789,
  "isRefunded": false,
  "isRevoked": false,
  "ownershipType": "purchased",
  "product": {
    "id": "product_id",
    "displayName": "Product Name",
    ...
  },
  "transaction": {
    "id": "1234567890",
    ...
  }
}
```

### StoreKitState Dictionary

```json
{
  "type": "purchaseSuccess",
  "productId": "product_id"
}
```

或

```json
{
  "type": "productsLoaded",
  "products": [
    {
      "id": "product_id",
      ...
    }
  ]
}
```

### RenewalInfo Dictionary

```json
{
  "willAutoRenew": true,
  "expirationDate": 1701715456789,
  "renewalDate": 1701715456789,
  "expirationReason": null
}
```

## 数据类型说明

### 时间戳
所有日期字段都转换为**毫秒时间戳**（Int64），例如：`1699123456789`

### 枚举值
所有枚举值都转换为字符串，例如：
- `ProductType`: `"consumable"`, `"nonConsumable"`, `"autoRenewable"`, `"nonRenewable"`
- `RenewalState`: `"subscribed"`, `"expired"`, `"inBillingRetryPeriod"`, `"inGracePeriod"`, `"revoked"`
- `OwnershipType`: `"purchased"`, `"familyShared"`
- `Environment`: `"production"`, `"sandbox"`, `"xcode"`

### 可选值
可选值在 Dictionary 中：
- 如果有值：正常显示
- 如果为 `nil`：使用 `NSNull()`（JSON 中为 `null`）

## Flutter 集成示例

```dart
// 在 Flutter 中接收转换后的数据
Future<void> onProductsLoaded(List<Product> products) async {
  // 转换为 JSON 字符串
  String? jsonString = StoreKitConverter.productsToJSONString(products);
  
  // 通过 MethodChannel 传递给 Flutter
  await methodChannel.invokeMethod('onProductsLoaded', jsonString);
  
  // 或者在 Flutter 端解析
  List<dynamic> productsList = jsonDecode(jsonString!);
  // 使用 productsList...
}
```

## 注意事项

1. **时间戳格式**：所有日期都转换为毫秒时间戳（Int64）
2. **JSON 序列化**：使用 `JSONSerialization` 进行序列化，确保所有值都是可序列化的类型
3. **可选值处理**：`nil` 值使用 `NSNull()` 表示，在 JSON 中为 `null`
4. **错误处理**：如果转换失败，`toJSONString` 方法会返回 `nil`
5. **性能考虑**：大量数据转换时，建议使用 `toDictionaryArray` 而不是逐个转换

## 完整示例

```swift
import StoreKit2Manager

// 1. 获取产品列表并转换
let products = StoreKit2Manager.shared.allProducts
let productsDict = StoreKitConverter.productsToDictionaryArray(products)
let productsJSON = StoreKitConverter.productsToJSONString(products)

// 2. 获取交易历史并转换
let histories = await StoreKit2Manager.shared.getTransactionHistory()
let historiesDict = StoreKitConverter.transactionHistoriesToDictionaryArray(histories)
let historiesJSON = StoreKitConverter.transactionHistoriesToJSONString(histories)

// 3. 监听状态变化并转换
StoreKit2Manager.shared.onStateChanged = { state in
    let stateDict = StoreKitConverter.stateToDictionary(state)
    let stateJSON = StoreKitConverter.stateToJSONString(state)
    
    // 传递给其他语言
    // ...
}

// 4. 获取续订信息并转换
if let renewalInfo = await StoreKit2Manager.shared.getRenewalInfo(for: "product_id") {
    let renewalInfoDict = StoreKitConverter.renewalInfoToDictionary(renewalInfo)
    let renewalInfoJSON = StoreKitConverter.renewalInfoToJSONString(renewalInfo)
}
```

---

**所有转换器已创建完成！** 🎉

