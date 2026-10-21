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
具体结果见GitHub Actions及CI artifact。源码中的历史Linux验证只代表历史范围，不冒充本次macOS结果。
