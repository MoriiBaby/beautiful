# Scene hosting: bounded reconstruction

**Gate: UNAVAILABLE.** `SRSceneHost` is a fail-closed ObjC++/Swift interface, not a working host. `SR_SCENE_HOSTING_IMPLEMENTED=0`, `isAvailable=NO`, `isAttached=NO`, `hostedView=nil`. Main packaging must remain disabled. No private calls, hooks, app launches, windows, screenshots, installation, attach, upload or authorization changes are introduced.

## Coordinates and independent evidence

Read-only input: `../stheno-audit-20261021/deb/data/Library/MobileSubstrate/DynamicLibraries/Stheno.dylib`; SHA256 `5fc39b0968bd282ba2be0c80909f6ba8aa0d22b9a904c1eebd41bca8ca9f82b7`. arm64e slice starts at file `0xbc000`, UUID `ccc29038d46a372086f319d0f73a9d33`. Addresses below are unslid slice VAs, not live pointers. Instruction source: `binary-evidence/Stheno-arm64e-fulltext.txt`. Swift field names were cross-checked against `BINARY-SWIFT-TYPES.md`; old reconstructed source/headers are not specifications.

`Tests/test_scene_contract.py` independently reads Mach-O load commands/imports/chain starts. Observed pointer format is **12 (ARM64E_USERLAND24)**: next=(raw>>51)&0x7ff, stride **8**, bind ordinal **24 bits**, auth rebase target low32+image base; unauth rebase target43/high8. Both bind/auth bits are handled. No generic PAC mask, no copied old decoder. Important resolved slots:

| Slot | Actual target |
|---|---|
| `a62a8` | `_createSceneWithDefinition:settings:initialClientSettings:transitionContext:fromRemnant:usingClientProvider:completion:` |
| `a6330` | `client:didUpdateClientSettings:withDiff:transitionContext:` |
| `a62c8` | `_scene:interceptUpdateWithNewSettings:` |
| `a62d0` | `_setDeactivationReasons:onScene:withSettings:reason:` |
| `a6670`, `a6678` | imported `FBScene`, `UIMutableApplicationSceneSettings` classes |

This fixes the disassembler's “bad class ref” annotations. Selectors alone do not prove their framework method encodings or ownership.

## Proven original minimum chain / ABI bounds

1. **Acquire, not independently create.** `15744 -> 157ac:2ba24` enumerates `FBSceneManager.sharedInstance` scenes (`2bb28..2bb60`), matching a client's bundle ID. The enumeration block descriptor at `9e710`, signature pointer slot `9e730 -> 7fe50`, is `v16@?0@"FBScene"8` (one FBScene argument, NOT scene+stop pointer). If absent, `157e0 -> 15618`, then `15698..156b0` requests `UIApplication.sharedApplication launchApplicationWithIdentifier:suspended:` with object ID and boolean **1**. The helper `59194` packs object at +8 and one boolean byte at +16. No owned scene definition is constructed here.
2. **Creation observation.** Selector registration `774c8..774d8`; ObjC entry `775d4..77698` forwards seven object-like arguments to `774dc`/Swift `60c58`. Original IMP call `76fd8 -> 77038..77060`: x0=self, x1=selector, x2..x7=first six arguments, seventh at caller SP; object result retained via `objc_retainAutoreleasedReturnValue`. The `fromRemnant` x6 input is retained at `77650..77654`: do NOT guess it is BOOL. `60d88` calls original, casts result to FBScene, matches `clientProcess.bundleIdentifier`, dispatches to main; `61150..611bc` retains/replaces manager.scene (+0x18), then activates. This is borrowing a SpringBoard-created scene, not proof of exclusive ownership or a destroy API.
3. **Foreground transition.** `14184 -> 1b73c/1b71c`: scene.uiSettings.mutableCopy, cast to UIMutableApplicationSceneSettings, `1429c..142a4 setForeground:YES`, `142c0..142dc updateSettings:withTransitionContext:completion:` with settings, nil context, completion. Completion block descriptor `9e1c0`, signature pointer `9e1e0 -> 7f82a = v8@?0`, invokes `1b4f4 -> 14350`. Result of this dynamic settings call is ignored; that is NOT independent proof of a void method encoding.
4. **Real layer-host view, not UIWindow or snapshot.** Scene client-settings hook calls `5f760 -> 5f784:14d9c`; `5eff8..5f04c` reads `layers` and casts to NSOrderedSet. `14d9c` iterates layers; `14ee8` asks `isKeyboardLayer`. Nonkeyboard branch `15018..15114` allocates `_UIContextLayerHostView` (class-name initializer `2c5b0`) and sends `initWithSceneLayer:` with one object. Keyboard branch `14f40..14ffc` uses `_UIKeyboardLayerHostView initWithKeyboardLayer:owningScene:` with two objects. Result must cast to UIView; arrays retain these views. This proves real host-view construction, **not** independently working touch/focus routing or layer replacement/invalidation.
5. **Resize actually observed.** `65cd4` returns the real UIView with clipsToBounds=NO; `65d1c..65e34` sets a scale/rotation CGAffineTransform. UIKit setter uses x2 pointing at the 48-byte transform (six doubles, non-HFA). This is a display transform of a hosted layer, not proof of a remote FBScene frame-resize protocol. Completion `14350` changes launching state and later updates transition settings (`14ac4`). No arbitrary scene-size setter is justified by these addresses.
6. **Close has two distinct meanings.** `15700 -> 14bec`: if scene exists, setForeground:NO only when it is not frontmost (`14c18..14d1c`), clear published views (`14d28..14d50`), release scene and write Swift optional sentinel 1 (`14d54..14d60`). Another path `15828` calls `deactivateWithTransitionContext:nil`, then `clientProcess _killForReason:andReport:withDescription:completion:` (`158c8..15970`, reason 1, report 0, nil description). Killing a borrowed app is NOT clean host teardown; no such behavior is implemented.

7. **Presenter and touch are no longer generic blockers.** The ReflectManager `presenter` field (`938fc`, type Dynamic?) uses offset slot `b3be8`: constructor `16610/16838..1683c` stores optional sentinel 1, destructor `15cb0..15cbc` releases it; no active presenter creation/send was found. The actual route is the layer-host views above. Independent ObjC method-list decoding proves SthenoWindow `hitTest:withEvent:` at `104f0` has encoding `@40@0:8{CGPoint=dd}16@32`; `1053c -> 103dc -> 10424` calls super, then rejects only the empty `_UIHostingView<Container>` hit. `touches*` selectors at `72b74/72c5c/72df8/72ee0` belong to `_SBFluidSwitcherPanGestureRecognizerHook` (accessor `5bc00`), not an app touch-forwarding implementation.

The original `_msg_send` at `70ba0..70bfc` blindly loads integer/SIMD argument buffers and calls objc_msgSend. It performs no method-encoding validation. Swift tuple widths and ignored return values in its callers must not be promoted into verified external declarations.

## Exact stopping points / work required to unlock

- 本轮已获用户批准，采集了 iOS16.0.3 RootHide SpringBoard 的指定方法编码，见 `Device/Results/springboard-metadata-20261021T082940Z.json`。场景枚举、updateSettings、两个层宿主init、setTransform等编码已实测，解除这部分ABI未知；但未调用它们的业务实现。iOS15.4.1尚未采集。方法编码不建立callback queue/cancellation、层所有权或跨系统语义，后续仍需OS allowlist和逐次runtime核验。
- The acquisition chain borrows a system scene by bundle ID. It does not resolve multiple scenes of one app or give an exclusive ownership lease. A new host must track scene identity/generation and never destroy or terminate an unrelated, reused, or frontmost scene.
- Real rendering alone cannot establish interactive hosting. Need layer-change handling, event/focus routing through `_UIContextLayerHostView`, and coordinate correctness after transform. The original also intercepts settings/deactivation (`a62c8`, `a62d0`); blindly installing those broad hooks is outside a safe minimal adapter. No screenshot/window fallback is permitted.
- Need a proved detach/restore sequence, including pending activation/completion and layer replacement. Static releases/sentinel writes are not a cancellation contract. Neither unconditional setForeground:NO nor process kill is acceptable cleanup of a borrowed scene.

These are core-hosting blockers, not merely the absence of an SDK. This stage does not claim reconstruction is impossible. A later explicitly authorized native/runtime validation must prove launch -> live input -> transformed input/resize -> close with no stale host, no pending callback resurrection and no unrelated app termination before the gate can change.

## Current Swift contract and validation

Include `SRSceneHost.h` in the Swift bridge header and compile `.mm` with ARC. Intended import: `try host.attach(bundleIdentifier: id, to: view)`, `try host.resize(to: bounds)`, `try host.close()`.

Every mutating method requires main thread. Attach validates nonempty NSString and UIView, then throws Unavailable without retaining/modifying the view or launching anything. Resize rejects nonfinite/zero/negative geometry, otherwise throws Unavailable; it never reports success by resizing an empty container. Close is idempotent local cleanup only: main-thread success means no resource was acquired, NOT that a remote scene was closed. Errors use `SRSceneHostErrorDomain` and stable codes 1=Unavailable, 2=InvalidArgument, 3=MainThreadRequired. Availability/attachment remain false after close or failures. Added safety behavior differs from the original's unguarded dynamic sends and process-kill action; no licensing/signature behavior is bypassed.

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p test_scene_contract.py -v`.
Result: 3 scene source/evidence tests passed locally (fail-closed guards, disabled layer-lab ownership wiring, independent original fixups/block signatures/BL edges), plus 4 saved-device-evidence checks. When the audit is absent, the original binary-evidence test explicitly skips. These are **not** executable UIKit function tests. This round also compiled Shared, SRSceneHost, SRLayerHostCandidate and SRMainBridge against the real iOS SDK for arm64 and arm64e: `Tools/Build/compile-scene-20261021T083500.132455Z/build.json`. Swift import, main linking/load, interactivity, remote scene resize and teardown remain UNVERIFIED. Do not package the main feature as restored.

## 本轮已实现的独立层宿主实验代码

`SRLayerHostCandidate.h/.mm` 恢复了“显式传入借用 FBScene 和 NSOrderedSet layers → runtime精确核验 isKeyboardLayer/alloc/init → 构造真实context/keyboard host UIView → 维护自有数组 → CGAffineTransform显示变换 → 主线程清理自有视图”子链。init的消耗self和+1返回写在函数类型中，调用已核验的同一个IMP；不注册任意方法、不猜CGRect传参、不伪造截图。类名/参数类型限制根据runtime元数据检查，非法结构拒绝。

默认 `SR_ENABLE_LAYER_HOST_LAB=0`，没有入口调用它，公开 `SRSceneHost` 仍不可用。这个candidate没有取得scene/foreground，也未把host放到可见窗口、验证触摸、处理远端销毁/更新，不是完整浮窗实现。禁用lab与新窗口交互候选一样，均不能充当主功能恢复证据。编译通过只证明语法/类型/目标对象可生成。
