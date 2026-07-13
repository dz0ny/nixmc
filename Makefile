# nixmc — build a proper macOS .app bundle
#
#   make            # release build → dist/nixmc.app
#   make run        # build the bundle and launch it
#   make dev        # swift run (fast, no bundle)
#   make sign       # codesign the bundle (ad-hoc, or SIGN_ID="Developer ID...")
#   make dmg        # package the bundle into dist/nixmc.dmg
#   make notarize   # sign+dmg, submit to Apple notary, staple ticket
#   make release    # sign → dmg → notarize → staple (full signed release)
#   make clean
#
# Notarized release example:
#   make release SIGN_ID="Developer ID Application: Jane (TEAMID)" NOTARY_PROFILE=nixmc
# (create the profile once: xcrun notarytool store-credentials nixmc \
#    --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW)

APP_NAME    := nixmc
BUNDLE_ID   := dev.dz0ny.nixmc
VERSION     ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo 0.0.0)
CONFIG      ?= release

BUILD_DIR   := $(shell swift build -c $(CONFIG) --show-bin-path 2>/dev/null)
BINARY      := $(BUILD_DIR)/$(APP_NAME)

DIST        := dist
APP         := $(DIST)/$(APP_NAME).app
CONTENTS    := $(APP)/Contents
MACOS       := $(CONTENTS)/MacOS
RESOURCES   := $(CONTENTS)/Resources
ICON        := Assets/AppIcon.icns

# Ad-hoc identity by default; override with `make sign SIGN_ID="Developer ID..."`
SIGN_ID     ?= -

# Notarization: set these (or export in the environment / CI secrets).
#   NOTARY_PROFILE  — a stored `notarytool store-credentials` keychain profile
#   -- or --
#   APPLE_ID, TEAM_ID, APP_PW  — Apple ID + team + app-specific password
NOTARY_PROFILE ?=
APPLE_ID       ?=
TEAM_ID        ?=
APP_PW         ?=

.DEFAULT_GOAL := app

.PHONY: app
app: $(APP)

$(APP): build Info.plist $(ICON)
	@echo "==> Assembling $(APP) ($(VERSION))"
	@rm -rf "$(APP)"
	@mkdir -p "$(MACOS)" "$(RESOURCES)"
	@cp "$(BINARY)" "$(MACOS)/$(APP_NAME)"
	@cp "$(ICON)" "$(RESOURCES)/AppIcon.icns"
	@sed 's/__VERSION__/$(VERSION)/g' Info.plist > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Bundle any SwiftPM resource bundles alongside the binary
	@for b in "$(BUILD_DIR)"/*.bundle; do \
		[ -e "$$b" ] && cp -R "$$b" "$(RESOURCES)/" || true; \
	done
	@echo "==> Built $(APP)"

.PHONY: build
build:
	@echo "==> swift build -c $(CONFIG)"
	@swift build -c $(CONFIG)

.PHONY: sign
sign: app
	@echo "==> codesign ($(SIGN_ID))"
	@codesign --force --deep --sign "$(SIGN_ID)" \
		--options runtime \
		--identifier "$(BUNDLE_ID)" \
		"$(APP)"
	@codesign --verify --verbose "$(APP)"

.PHONY: run
run: app
	@open "$(APP)"

.PHONY: dev
dev:
	@swift run

# Build the notarytool auth flags from whichever credentials are provided.
ifneq ($(NOTARY_PROFILE),)
NOTARY_AUTH := --keychain-profile "$(NOTARY_PROFILE)"
else
NOTARY_AUTH := --apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" --password "$(APP_PW)"
endif

.PHONY: notarize
notarize: dmg
	@if [ "$(SIGN_ID)" = "-" ]; then \
		echo "ERROR: notarization needs a real Developer ID."; \
		echo "  make notarize SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" NOTARY_PROFILE=nixmc"; \
		exit 1; \
	fi
	@echo "==> Submitting $(DIST)/$(APP_NAME).dmg to Apple notary service"
	@xcrun notarytool submit "$(DIST)/$(APP_NAME).dmg" $(NOTARY_AUTH) --wait
	@echo "==> Stapling ticket to app + dmg"
	@xcrun stapler staple "$(APP)"
	@xcrun stapler staple "$(DIST)/$(APP_NAME).dmg"
	@xcrun stapler validate "$(APP)"
	@echo "==> Notarized: $(DIST)/$(APP_NAME).dmg"

# Full release: build → hardened-runtime sign → dmg → notarize → staple
.PHONY: release
release:
	@$(MAKE) sign SIGN_ID="$(SIGN_ID)"
	@$(MAKE) notarize SIGN_ID="$(SIGN_ID)" \
		NOTARY_PROFILE="$(NOTARY_PROFILE)" \
		APPLE_ID="$(APPLE_ID)" TEAM_ID="$(TEAM_ID)" APP_PW="$(APP_PW)"

.PHONY: dmg
dmg: app
	@echo "==> Packaging $(DIST)/$(APP_NAME).dmg"
	@rm -f "$(DIST)/$(APP_NAME).dmg"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP)" \
		-ov -format UDZO "$(DIST)/$(APP_NAME).dmg"

.PHONY: clean
clean:
	@rm -rf "$(DIST)"
	@swift package clean

.PHONY: version
version:
	@echo $(VERSION)
