# StoreKitFlow SPM 发布教程

本文面向维护 StoreKitFlow 的开发者，介绍如何把 Git 仓库中的某个提交作为 Swift Package 版本提供给其他项目使用。项目通过 GitHub 仓库分发 SPM，不需要 CocoaPods 或额外的包注册操作。

仓库地址：<https://github.com/ppswdev/StoreKitFlow.git>  
包与产品名称：`StoreKitFlow`；Swift 模块：`import StoreKitFlow`。

## 一、先理解版本和标签

Xcode 按 Git 标签识别版本。推送 `main` 只更新分支；要让使用版本规则的项目找到新版本，还要将对应的版本标签推送到 GitHub。GitHub Release 页面是可选的，它用于展示发行说明，不能代替推送 Git 标签。

例如，`2.0.1` 是一个语义化版本号：主版本表示不兼容的 API 变更，次版本表示兼容的新功能，补丁版本表示兼容的问题修复。StoreKitFlow 2.x 的模块和 API 与 1.x 不同，因此从 1.x 升级到 2.x 需要调整接入代码。

在 Xcode 中，`Up to Next Major Version` 从 `1.1.2` 开始时，范围是 `>= 1.1.2` 且 `< 2.0.0`。即使后来发布了 `2.0.0`，这个 1.x 范围也不会自动升级到 2.x；需要手动修改依赖规则。详见 [Apple 的依赖配置说明](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)。

## 二、发布前检查

在终端进入仓库：

```sh
cd /Users/ppswdev/Desktop/Projects/Apps/StoreKitFlow
git status --short --branch
git remote -v
git diff
git tag --list
git ls-remote --tags --refs origin
```

如果仓库在其他位置，请把 `cd` 后的路径换成实际路径。确认远端地址、当前分支、准备发布的文件，以及本地和远端已有的标签。`git diff` 不包括未跟踪文件；也要根据 `git status` 检查它们。不要直接把 `.DS_Store` 等无关文件提交。

确认 `Package.swift`、README、变更记录与要发布的内容一致。本项目当前声明 Swift tools 6.0、iOS 17 和 macOS 14；实际可用工具链以 README 中的验证记录为准。避免把尚未验证的环境写成已验证。

运行单元测试：

```sh
swift test
```

如本次涉及 StoreKit 交易、权益或示例，选择可用的 iOS 模拟器，运行本地 StoreKit 集成测试：

```sh
xcrun simctl list devices available
xcodebuild -workspace StoreKitFlow.xcworkspace \
  -scheme StoreKitFlowExample \
  -testPlan StoreKitFlow \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

将目的设备名称替换为本机实际可用的模拟器；有同名设备时可用 `id=模拟器的UDID`。测试使用 `Example/StoreProducts.storekit` 模拟交易，测试会清理模拟交易数据。该测试不能代替真实 App Store Sandbox、TestFlight 或生产环境验收。未通过或未执行的检查应如实记录。

## 三、提交准备发布的代码

标签指向的是某个**提交**，不会自动包含尚未提交的文件。先检查并暂存确实要发布的修改；例如只发布教程文件时：

```sh
git add Docs/StoreKitFlow-SPM发布教程.md Docs/README.md
git diff --cached --check
git diff --cached
git status --short
git commit -m "Document SPM release process"
```

上面的文件和提交信息只是示例。实际发布还应按需暂存源码、测试、配置、README 和变更记录；检查后再提交。不要把不属于本次发布的本地配置一起提交。若暂存区为空，不必创建空提交。

推送要发布的分支。以下示例假设当前发布分支是 `main`，且具有仓库写入权限：

```sh
git branch --show-current
git log -1 --oneline
git push origin main
```

如果使用其他分支，替换为实际分支，并按照项目的合并流程把发布提交合入目标分支。身份验证失败时先检查 GitHub 账号和 Git 凭据；不要将令牌写入仓库或文档。

## 四、创建并推送版本标签

先决定版本号，检查本地和远端是否已存在：

```sh
git tag --list '2.0.1'
git ls-remote --tags --refs origin 'refs/tags/2.0.1'
```

`2.0.1` 只是示例，发布时替换为实际决定的版本号。若两条命令都没有输出，并且当前 `HEAD` 就是要发布的提交，可创建附注标签并推送这个标签：

```sh
git tag -a 2.0.1 -m "StoreKitFlow 2.0.1"
git show --no-patch --format=fuller 2.0.1
git rev-parse '2.0.1^{commit}'
git push origin refs/tags/2.0.1
```

已有本地标签时，不要直接假设它包含刚提交的修复；通过 `git show` 和 `git rev-parse` 比较标签指向的提交。若标签尚未发布且指向错误提交，可在确认它仅存在本地后重新创建；也可以选一个未使用的新版本号。**已推送或已被使用的版本标签不要改写或强制覆盖**：为修复创建新提交和新版本。

本项目曾出现 `2.0.0` 标签只在本地、且指向修复之前提交的情况。发布时以当次检查结果为准，先确认远端标签和要发布的提交，再决定使用哪个版本；不要盲目执行 `git push origin --tags`。

## 五、验证远端版本和 Xcode 接入

确认 GitHub 已收到标签，并与本地目标提交一致：

```sh
git ls-remote --tags origin 'refs/tags/2.0.1' 'refs/tags/2.0.1^{}'
git rev-parse '2.0.1^{commit}'
```

对于附注标签，远端带 `^{}` 的行是标签解引用后的提交 ID，应与本地 `rev-parse` 的结果一致；普通轻量标签则直接比较标签行的提交 ID。也可以在 GitHub 仓库的 Tags 页面查看。按需在 GitHub 创建 Release 并填写变更说明；创建 Release 并非 SPM 接入的必要步骤。

在另一个 Xcode 项目中选择 **File → Add Package Dependencies**，输入仓库地址，选择希望使用的版本范围，并把 `StoreKitFlow` 产品加入目标。针对本教程的 `2.0.1` 示例，可将起始版本设为 `2.0.1`，使用 **Up to Next Major Version**；它允许兼容的 2.x 更新，不会自动跨到 3.0.0。

验证项目能成功解析、构建并 `import StoreKitFlow`。在 Swift 包的 `Package.swift` 中，相同规则可写为：

```swift
.package(url: "https://github.com/ppswdev/StoreKitFlow.git", from: "2.0.1")
```

### 看不到新版本怎么办

1. 重新运行 `git ls-remote --tags --refs origin`，确认标签真的在远端，且拼写是期望的语义化版本。
2. 检查 Xcode 当前依赖的仓库 URL 和版本范围；1.x 的 `Up to Next Major Version` 不包括 2.0.0。
3. 如果依赖已经添加，在项目的 **Package Dependencies** 中修改版本规则，再通过 **File → Packages** 中的更新或解析操作重试。必要时检查 `Package.resolved` 的解析结果。
4. 若仍失败，检查 GitHub 访问权限、网络以及该标签对应提交中的 `Package.swift` 和工具链要求。

仅用于开发联调时，也可以选择远端分支或在 Xcode 中添加本地包；这不是发布版本，也不会把工作区中未提交的修改自动推送到 GitHub。

## 参考

- [Apple：Publishing a Swift package with Xcode](https://developer.apple.com/documentation/xcode/publishing-a-swift-package-with-xcode)
- [Apple：Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
- [Swift Package Manager：Adding dependencies](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/addingdependencies/)
