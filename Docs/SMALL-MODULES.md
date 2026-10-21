# 相机与键盘：恢复实现和证据映射

这是独立重建候选，不是原作者源码或已验证的完整恢复版。来源 SHA 和旧包保持在 `Docs/PLAN.md` 与 `Evidence/INPUTS.json`。二进制地址均是原 arm64e 静态 VA；宿主测试不运行 iOS Objective-C runtime。

| 原行为证据 | 生产实现 | 验收与边界 |
|---|---|---|
| Camera `0x4048/0x4068` 缺字典/键跳过，`0x4078` 才写开关；`0x412c` 每次刷新 | Camera/Camera.mm + Shared/SRPolicy.c `SRStickyFlagNext` | C 真编译执行16组bool组合、YES→缺失→显式NO历史；ObjC plist读取仅交叉编译，未真机执行 |
| Camera x2仅原样保存，x3 retain，不能据此证明两个参数全是id | `SRCameraTryInstall<Condition>` | 仅返回void、第二参数对象且第一参数精确匹配 q/Q/i/I/B/@ 对应类型才安装；其他签名禁用，不猜 |
| Keyboard `0x43b4–0x4494` 字符串 Apps 空格拆分 + ctor bundle筛选 | `SRKeyboardBundleAllowed` | 类型非法拒绝；不接受原报告误称的数组协议 |
| `0x419c–0x4300` 读frontmost/id；`0x46cc`先刷新再调原activeInstance | `SRKeyboardReadFrontmost`/`SRKeyboardActive` | 文件/解析/键缺失保留旧值；接线测试检查顺序，无env读写与frontmost写回 |
| `0x44bc–0x4540` keyboardImpl→delegateAsResponder→canResign→resign | `SRKeyboardDismissResponder` | 每步检查实际runtime ABI，通知注册失败则禁用行为 |
| `0x4744–0x474c` 只有字符串比较返回NO且window非nil才进几何 | `SRKeyboardShouldResize` | 真C全4组合，特意覆盖旧审计曾反读的比较极性 |
| `0x4754`临时关screen hook；`0x4780–0x47f8`主屏横屏方形frame/bounds，最后开hook | `SRKeyboardWindow` + `SRKeyboardGeometryForScreen` | 真C 2601组几何网格；有显式@finally复位；未验证UIKit实际可见结果 |
| `0x482c–0x487c` 保存首scene并读169；`0x4880–0x48cc`169 AND hookScreen转发scene | `SRKeyboardScene`/`SRKeyboardBounds` | 真C全4 AND组合；C init wrapper显式ns_consumed/self和ns_returns_retained/+1；scene同名方法ABI不符则调原screen |
| 原__data `0xc160`初值1，169在common初值0 | `gHookScreen=YES`、`gMode169=NO` | 两slice直接读取字节核对，非注释猜测 |

## 刻意的安全差异（不宣传逐字节/所有输入100%等价）

- 每个模块必须读取新域 `com.local.stheno.reconstruction.plist` 中 NSNumber `EnableReconstruction=YES` 才有行为；默认不激活。此文件未自动创建，原偏好未改。
- 发现本进程已载入原三模块任一名称/原窗口类时不激活；包元数据也与原包冲突，防止覆盖和重复Hook。不能保证对手工注入/后续加载的所有排列均自动阻断，设备验证仍须严格单包A/B。
- 相机仍读取原域 Camera，键盘仍读取原域 Apps/169 和原frontmost协议，便于与原规格对照；不会主动改写这些文件。没有主生产端时键盘不算端到端完整。
- 相机缓存使用编译器原子读写避免C++数据竞争；缺数据保旧行为不变。
- 配置/IPC 畸形类型现在拒绝，避免原可能的 selector 异常。这是安全防护，不是模拟原程序的崩溃行为。
- 四个键盘目标先全部检查返回值/参数数目/分量类型，再逐项Substrate安装；安装不是事务。任何缺原IMP/通知注册失败时已安装wrapper退为原样转发，不宣称原子回滚或卸钩成功。
- method selector存在不是兼容验证；runtime检查同样不能证明系统内部语义、线程/重入和输入路由适配。
- 不复制原日志函数，不杀mediaserverd，不重启SpringBoard，不自动注入/安装。

## 本轮可证明与不可证明

`Tests/test_policy.py` 直接编译生产C为Linux共享库执行；`test_small_modules.py` 检查Objective-C接线与负向变异。这不是运行iOS Hook。`Tools/build.py` 真实SDK的arm64/arm64e编译链接结果另见BUILD文档/构建manifest；链接只核开发stub导出，不证明设备上存在对应runtime、可加载或生效。

必须另外验收：实际私有方法完整编码、RootHide加载/签名/PAC、配置值翻转与缺失、Apps内外进程、前台id一致/不一致、竖横屏、scene生命周期和键盘焦点。主scene后端未完成，当前不会生成完整恢复DEB。
