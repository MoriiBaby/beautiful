# GitHub macOS 验证计划

## 本轮范围
用户明确授权上传至公开 MoriiBaby/beautiful，并参考 roothide/theos 进行云端 Mac 构建；采用新分支 rebuild/stheno-dev1-macos，不覆盖 main，不创建 Release/Tag、不安装设备。

## 固定源码与保密
上传当前独立重建源码、测试、构建工具和必要说明。排除 Device/、Evidence/、原包/附件/SDK和旧编译产物，凭据仅在本机通过 STATUSBARSPEED 引用，不存入仓库或 workflow。仓库内无运行时设备地址/进程ID/采集记录。

## 成功标准
1. 本机 source guards、生产C策略与接线测试通过。依赖未提供的本地二进制/设备证据测试明确skip，不计成功。
2. 官方 roothide/theos 固定提交＋固定 headers/lib 子模块，云端 macOS 使用 Xcode Apple clang/linker，以 roothide scheme 编译 Camera/Keyboard 的 arm64/arm64e。
3. 独立解析最终产物CPU subtype、minOS15、ID/依赖/初始化入口与符号；arm64e不能被降级；不改Mach-O头冒充。
4. 禁用的 SceneBridge/Swift 候选由真实 Apple SDK 编译成对象，仅检查可编译性，不链接/发布主模块。
5. 上传CI artifact，下载复核成员/大小/SHA及manifest绑定的提交。报告具体run/commit、测试/编译/未验证边界。

## 独立失败信号与边界
- Token/私有数据进入候选文件：拒绝提交/推送。
- 非预期仓库写入、旧分支覆盖或安装动作：停止。
- Apple arm64e编译/链接/验证失败：查看真实日志修根因，不能删架构/放宽未定义符号/伪造通过。
- 主模块不完整门禁保持关闭；最终两个dylib是开发编译证据，不是完整Stheno恢复包，无DEB/Release/设备功能结论。

## 验证记录

已完成的实际结果：

- Commit `0b10630f60a89efe84d917ffc7fd0fb0f28558e3`：首次 Mac 构建失败，原因是 runner 缺 `rg`；未进入编译。
- Commit `0d71698191649e348beae3623808a7a742fa664e`：Actions run `39587719447` 成功，job `119180680645` 成功。
- 云端工具链：Xcode 26.6 / iPhoneOS SDK 26.5；RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`；headers `744ee65cd464becd8b06cab6eaeffc0512b371f1`；lib `85e9b5b8aff11bbefc59525c64c8f55149926e56`。
- Camera 和 Keyboard 均生成 arm64 + arm64e、minOS 15.0、RootHide install name/依赖和 ldid 开发签名，真实 Mach-O 验证通过。
- 禁用的 SceneBridge、异步场景会话、窗口策略和 Swift 候选对象均编译通过；没有链接/激活主模块。
- Artifact `stheno-rebuild-dev1-small-0d71698191649e348beae3623808a7a742fa664e`，GitHub artifact id `12340547197`，大小 259936 字节，下载 ZIP SHA-256 `8f86ae9bd67ba85e271e895c874ce4e9da718f9c265b78c3a966cccffbad555e`。

这些只证明云端构建和静态产物验证通过，不证明设备加载、相机/键盘功能、应用场景交互或关闭恢复。源码中的历史 Linux 验证只代表历史范围，不冒充本次 macOS 结果。
