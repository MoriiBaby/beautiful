# Independent SMALL MODULES ONLY. Root main/packaging guard is not bypassed.
# Invoke from repository root: gmake -f CI/SmallModules.mk all
.DEFAULT_GOAL := all
TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
DEBUG := 0
FINALPACKAGE := 1
# Official common.mk otherwise takes notdir(first MAKEFILE_LIST), losing CI/.
export _THEOS_PROJECT_MAKEFILE_NAME := CI/SmallModules.mk

ifneq ($(filter package install stage do reinstall uninstall,$(MAKECMDGOALS)),)
$(error CI builds libraries only; packaging/device operations disabled)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := SthenoRebuildCamera SthenoRebuildKeyboard
SR_SHARED_FILES := Sources/Shared/SRRuntime.mm Sources/Shared/SRPolicy.c
SthenoRebuildCamera_FILES := Sources/Camera/Camera.mm $(SR_SHARED_FILES)
SthenoRebuildKeyboard_FILES := Sources/Keyboard/Keyboard.mm $(SR_SHARED_FILES)
SthenoRebuildCamera_FRAMEWORKS := Foundation CoreFoundation
SthenoRebuildKeyboard_FRAMEWORKS := Foundation CoreFoundation UIKit CoreGraphics
SthenoRebuildCamera_LIBRARIES := substrate roothide c++
SthenoRebuildKeyboard_LIBRARIES := substrate roothide c++
SthenoRebuildCamera_CFLAGS := -ISources/Shared
SthenoRebuildKeyboard_CFLAGS := -ISources/Shared
SthenoRebuildCamera_OBJCFLAGS := -fobjc-arc
SthenoRebuildKeyboard_OBJCFLAGS := -fobjc-arc
SthenoRebuildCamera_CCFLAGS := -std=c++17
SthenoRebuildKeyboard_CCFLAGS := -std=c++17
# Enforce real symbol resolution, never -undefined dynamic_lookup.
SthenoRebuildCamera_LDFLAGS := -Wl,-undefined,error
SthenoRebuildKeyboard_LDFLAGS := -Wl,-undefined,error
SthenoRebuildCamera_INSTALL := 0
SthenoRebuildKeyboard_INSTALL := 0

include $(THEOS_MAKE_PATH)/tweak.mk
