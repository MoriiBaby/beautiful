# The default cannot claim a complete restoration. No install/package/stage path.
.DEFAULT_GOAL := all
PYTHON ?= python3
SHELL := /bin/sh

ifneq ($(filter package install reinstall uninstall stage do internal-install internal-package,$(MAKECMDGOALS)),)
$(error Packaging/staging/device operations are disabled; the main hosting gate is incomplete)
endif

ifneq ($(STHENO_THEOS_INTERNAL),1)
.PHONY: all full theos-compile preflight local-preflight deps-fetch deps-verify local-compile local-link scene-compile source-guard test build-tests help
all: full
full theos-compile:
	$(PYTHON) Tools/build.py main-guard
	$(MAKE) STHENO_THEOS_INTERNAL=1 all
preflight:
	$(PYTHON) Tools/build.py preflight
local-preflight:
	$(PYTHON) Tools/build.py local-preflight
deps-fetch:
	$(PYTHON) Tools/deps.py fetch
deps-verify:
	$(PYTHON) Tools/deps.py verify
local-compile: source-guard
	$(PYTHON) Tools/build.py compile
local-link: source-guard
	$(PYTHON) Tools/build.py link
scene-compile: source-guard
	$(PYTHON) Tools/build.py scene-compile
source-guard:
	$(PYTHON) Tools/guard.py
build-tests:
	$(PYTHON) -m unittest discover -s Tools -p 'test_*.py' -v
test: source-guard build-tests
	$(PYTHON) -m unittest discover -s Tests -p 'test_*.py' -v
help:
	@echo 'deps-fetch / deps-verify: pinned public real SDK + headers/stubs, external cache'
	@echo 'local-preflight: ObjC only; preflight: full Swift/main readiness (expected blocked)'
	@echo 'local-compile: arm64 + arm64e objects; local-link: both requested, any subtype downgrade fails'
	@echo 'scene-compile: ObjC scene + main C bridge only, NOT Swift or restored scene hosting'
	@echo 'test: source/package guards + build unit checks + project host tests; NOT device validation'
	@echo 'all/full/theos-compile: blocked pending main closure and Mac/RootHide Swift toolchain'
else
# Future Mac compilation entry: not a package target and not activated by local builds.
_MAIN_READY := $(shell $(PYTHON) Tools/build.py main-guard >/dev/null 2>&1 && echo ready)
ifneq ($(_MAIN_READY),ready)
$(error Main not ready; run make preflight for actionable blockers)
endif
ifeq ($(strip $(THEOS)),)
$(error Set THEOS to a complete official RootHide Theos installation on macOS)
endif
ARCHS := arm64 arm64e
TARGET := iphone:clang:15.6:15.0
THEOS_PACKAGE_SCHEME := roothide
FINALPACKAGE := 0
DEBUG := 1
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := SthenoRebuildCamera SthenoRebuildKeyboard SthenoRebuildMain
SR_SHARED_FILES := $(sort $(wildcard Sources/Shared/*.c Sources/Shared/*.mm))
SthenoRebuildCamera_FILES := $(sort $(wildcard Sources/Camera/*.mm)) $(SR_SHARED_FILES)
SthenoRebuildKeyboard_FILES := $(sort $(wildcard Sources/Keyboard/*.mm)) $(SR_SHARED_FILES)
# Orion preprocesses .x.swift automatically. Plain Swift stays plain Swift.
SthenoRebuildMain_FILES := $(sort $(wildcard Sources/Main/*.swift Sources/Main/*.mm Sources/Main/SceneBridge/*.mm)) $(SR_SHARED_FILES)
SthenoRebuildCamera_FRAMEWORKS := Foundation CoreFoundation
SthenoRebuildKeyboard_FRAMEWORKS := Foundation CoreFoundation UIKit CoreGraphics
SthenoRebuildMain_FRAMEWORKS := Foundation CoreFoundation UIKit CoreGraphics
SthenoRebuildCamera_LIBRARIES := substrate roothide c++
SthenoRebuildKeyboard_LIBRARIES := substrate roothide c++
SthenoRebuildMain_LIBRARIES := substrate roothide c++
SthenoRebuildCamera_CFLAGS := -I$(THEOS_PROJECT_DIR)/Sources/Shared
SthenoRebuildKeyboard_CFLAGS := -I$(THEOS_PROJECT_DIR)/Sources/Shared
SthenoRebuildMain_CFLAGS := -I$(THEOS_PROJECT_DIR)/Sources/Shared
SthenoRebuildCamera_OBJCFLAGS := -fobjc-arc
SthenoRebuildKeyboard_OBJCFLAGS := -fobjc-arc
SthenoRebuildMain_OBJCFLAGS := -fobjc-arc
SthenoRebuildCamera_CCFLAGS := -std=c++17
SthenoRebuildKeyboard_CCFLAGS := -std=c++17
SthenoRebuildMain_CCFLAGS := -std=c++17
SthenoRebuildMain_SWIFT_VERSION := 5
SthenoRebuildMain_SWIFT_BRIDGING_HEADER := Tools/SthenoRebuildMain-Bridging-Header.h
SthenoRebuildMain_ORION_DEFAULT_BACKEND := Substrate
# No staging until there is an explicitly reviewed complete package design.
# Filters live in Filters/ as evidence/templates; no root plist aliases are generated.
SthenoRebuildCamera_INSTALL := 0
SthenoRebuildKeyboard_INSTALL := 0
SthenoRebuildMain_INSTALL := 0
include $(THEOS_MAKE_PATH)/tweak.mk
endif
