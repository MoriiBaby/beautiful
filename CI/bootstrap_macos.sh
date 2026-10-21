#!/bin/bash
set -euo pipefail
# Public dependencies only. The local upload credential is never passed to Actions.
: "${THEOS:?Set THEOS outside the source checkout}"
[[ "$(uname -s)" == Darwin ]] || { echo 'Apple macOS/Xcode is required'; exit 2; }
for package in make ldid xz; do
  if ! brew list --versions "$package" >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install "$package"
  fi
done
command -v gmake
command -v ldid
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-path
xcrun --sdk iphoneos clang --version
xcrun --sdk iphoneos swiftc --version
pin=cfba89a53a05b4a1b822121158acc3669c20602f
if [[ ! -d "$THEOS/.git" ]]; then
  git clone --no-checkout https://github.com/roothide/theos.git "$THEOS"
fi
git -C "$THEOS" checkout --detach "$pin"
# These fixed submodules provide real headers/runtime stubs; no full Swift/Orion build is claimed.
git -C "$THEOS" submodule update --init --recursive
[[ "$(git -C "$THEOS" rev-parse HEAD)" == "$pin" ]]
[[ "$(git -C "$THEOS/vendor/include" rev-parse HEAD)" == 744ee65cd464becd8b06cab6eaeffc0512b371f1 ]]
[[ "$(git -C "$THEOS/vendor/lib" rev-parse HEAD)" == 85e9b5b8aff11bbefc59525c64c8f55149926e56 ]]
# No project source or device binaries are sent to dependency repositories.
