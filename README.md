# Stheno 独立源码重建（未完成）

本仓库保存遗失源码后的**独立重建候选**，不是原作者源码，也不是完整恢复版。原 DEB、旧源码附件、SDK、设备采集和凭据不在公开仓库中。

## 当前内容

- `Sources/Camera`：Camera 开关保持语义、RootHide 真路径、逐签名选择的 Hook。
- `Sources/Keyboard`：Apps 字符串筛选、前台 JSON 消费、responder 通知、scene/169/几何处理。
- `Sources/Shared`：生产 C 策略、精确 ABI 核验、默认 opt-in 关闭和原包共存拦截。
- `Sources/Main`：主浮窗候选现在包含异步 `SRSceneSession`：唯一场景选择、精确 ABI、真实图层接入、刷新、取消和关闭恢复状态机；**前台所有权 provider 尚未实现，公开入口默认不可用**。

相机、键盘也尚无安装后的设备功能验证。宿主测试、对象编译、动态库链接不能替代可用性和稳定性验收。

## GitHub 云端 Mac 构建

工作流 `.github/workflows/macos-small-modules.yml` 使用 `macos-26`、Xcode Apple clang/linker，以及官方 [roothide/theos](https://github.com/roothide/theos) 固定提交：

```
cfba89a53a05b4a1b822121158acc3669c20602f
```

1. 执行生产 C 策略和源码接线测试；私有原件/设备证据未提供的测试明确跳过。
2. `CI/SmallModules.mk` 只编译链接 `SthenoRebuildCamera`、`SthenoRebuildKeyboard`，保留 arm64、arm64e，最低 iOS15。
3. 独立解析最终 Mach-O，严格核验两架构、minOS、RootHide 依赖及签名，不修改头伪造通过。
4. 对禁用的主场景 ObjC++ / Swift 候选做对象编译；**不等于主浮窗已恢复或 Orion 入口已完成**。
5. 产出 CI artifact：两个开发动态库、编译候选对象及验证报告，不生成 DEB、不创建 Release、不安装设备。

Theos 的 `all` 会用 ldid 做开发 ad-hoc 签名。产物不是“未签名文件”，也不是已验证可安装包。云端实际运行状态以对应提交的 Actions 和 artifact 为准，本文不预先宣称构建通过。

## 本地检查

```sh
python3 Tools/guard.py
python3 -m unittest discover -s Tests -v
```

有已就绪 Mac/Xcode/RootHide Theos 时：

```sh
export THEOS=/absolute/path/to/theos
bash CI/build_small_modules.sh
python3 CI/verify_artifacts.py
python3 CI/compile_candidates.py
```

根 Makefile 的完整恢复/打包/安装门禁仍关闭。专用 CI 入口只验证已存在源码，不能绕过真实场景、触摸焦点、关闭恢复和生命周期验收。

新包预留身份 `com.local.stheno.reconstruction` / `0.1.0~dev1`；声明与原包冲突，不覆盖/冒充原版。开发行为默认关闭。

细节见 `Docs/CLOUD-PLAN.md`、`Docs/SMALL-MODULES.md`、`Docs/SCENE-HOSTING.md` 和 `Docs/SCENE-SESSION.md`。
