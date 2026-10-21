# Sources/Main：当前状态

本目录包含窗口管理候选代码和场景桥接接口。**不具备已验证的真实应用场景后端，不允许打包/激活主模块。**

- `SRFloatingCoordinator.swift`：新设计的最小窗口/标题栏/关闭/拖动/缩放，以及失败时清理、重复打开去重。只在 backend available 且 attach 成功后显示窗口；不是原版所有手势的精确恢复。
- `SRMainBridge.h/.mm`：稳定 C 函数桥接到 `SRSceneHost`，供 Swift 使用，不隐式安装 Hook。
- `SceneBridge/SRSceneHost.*`：场景恢复证据与状态由 `Docs/SCENE-HOSTING.md` 说明。若 `SR_SCENE_HOSTING_IMPLEMENTED=0`，attach/resize 明确失败，绝不能把它改成直接 return YES 骗过构建门禁。

当前没有提供会自动显示空壳的 Orion 入口，也没有把旧字符串 Hook 表恢复成可执行业务。Orion 正确 `.x.swift` 预处理/`Tweak` 入口规范已在官方文档核对；等真正场景承载链可以落地后再连接入口，而不是先生成日志型“主模块”。

本机没有 Swift 编译器。本目录 Swift 目前未原生类型检查；Objective-C++ 可用真实 SDK 独立编译不代表 Swift 通过或主功能可用。
