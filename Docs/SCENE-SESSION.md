# Scene session candidate — current implementation

## Scope

`SRSceneSession` is now an executable Objective-C++ candidate, but its public availability remains disabled by `SR_ENABLE_SCENE_SESSION_LAB=0`. It is not linked into an active main tweak and has not been run against a device.

## Implemented chain

1. Require SpringBoard, RootHide runtime opt-in, iOS 16.0.3 allowlist, and layer-host lab enablement.
2. Resolve `FBSceneManager +sharedInstance` and enumerate scenes using the measured `v24@0:8@?16` callback.
3. Match bundle identifier and optional unique scene identifier; reject ambiguity and enumeration/lookup disagreement.
4. Optionally request one suspended app launch using measured `B28@0:8@16B24`, but the current bridge passes `launchIfMissing:NO` because launch ownership and the resulting scene lease are not yet verified.
5. Verify scene identity before and after every private operation: scene pointer, identifier, and `clientProcess.bundleIdentifier`.
6. Read a fresh mutable UI settings copy. Already-foreground scenes are borrowed without writing or claiming that field. Background scenes require an injected `SRSceneSessionForegroundAuthority`; absence of that provider rejects the foreground mutation.
7. For an admitted foreground scene, read `clientSettings.layers`, create actual `_UIContextLayerHostView` / `_UIKeyboardLayerHostView` objects through the existing exact-ABI layer candidate, attach them to the caller's live UIView, apply a finite display transform, and only then deliver open success.
8. Refresh layers by pointer identity, replacing only this session's own host views. On identity/layer/window failure, detach owned views and enter bounded close.
9. Close invalidates the generation before cleanup; pending callbacks cannot reveal a hidden window. Foreground restoration is attempted only with an explicit lease proving the exact scene/revision was changed by this session. Otherwise it reports unresolved and performs no blind settings write or process termination.

## Explicitly not solved

- No reliable `SRSceneSessionForegroundAuthority` implementation exists yet. This is intentional. The old code's unconditional `setForeground:YES/NO` would risk mutating another actor's or frontmost scene's state.
- No real interactive input/focus validation, scene layer replacement notification, rotation coordinate test, or 15.4.1 ABI sample exists.
- The candidate does not kill the app on close, does not install broad FrontBoard hooks, and does not independently create an owned FBScene definition.
- `SRSceneHost` public gate remains unavailable; main package gate remains disabled.

## Verification

- `SRSessionPolicy.c` is the production state/ownership policy; `Tests/test_session_policy.py` executes that C implementation via a host library and covers timeout, ambiguity, generation, late callbacks, cancellation and ownership failures.
- `SRSceneSession.mm`, `SRSessionPolicy.c`, `SRMainBridge.mm`, layer bridge and window policy compile as arm64/arm64e iOS objects against the real SDK in `Tools/Build/compile-scene-20261021T103950.401850Z/build.json`.
- The cloud branch separately compiles disabled scene/Swift candidates on macOS. No device load or scene call has been performed.
