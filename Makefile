APP_NAME      := Vitals
DISPLAY_NAME  := Vitals
BUNDLE_ID     := dev.vstack.vitals
EXEC          := VitalsApp
CONFIG        := release
SIGN_IDENTITY := Vitals Local Signing

BUILD_DIR     := .build/$(CONFIG)
DIST          := dist
APP           := $(DIST)/$(APP_NAME).app
CONTENTS      := $(APP)/Contents
MACOS         := $(CONTENTS)/MacOS
RESOURCES     := $(CONTENTS)/Resources

.PHONY: all app build bundle sign run selftest render-samples clean

all: app

build:
	swift build -c $(CONFIG)

selftest:
	swift run -c $(CONFIG) vitals-selftest

app: bundle sign
	@echo "Built $(APP)"

bundle: build
	@rm -rf "$(APP)"
	@mkdir -p "$(MACOS)" "$(RESOURCES)"
	@cp "$(BUILD_DIR)/$(EXEC)" "$(MACOS)/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(RESOURCES)/AppIcon.icns"; fi
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@echo "Assembled $(APP)"

sign:
	@if security find-identity -p codesigning 2>/dev/null | grep -qF "$(SIGN_IDENTITY)"; then \
		echo "Signing with '$(SIGN_IDENTITY)'"; \
		codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(APP)"; \
	else \
		echo "No '$(SIGN_IDENTITY)' identity — signing ad-hoc."; \
		codesign --force --sign - --timestamp=none "$(APP)"; \
	fi
	@codesign --verify --verbose "$(APP)" && echo "Signed: $(APP)"

run: app
	@open "$(APP)"

render-samples: build
	@mkdir -p "$(DIST)/renders"
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/main-light.png" --appearance light --surface main
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/main-dark.png" --appearance dark --surface main
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/menu-light.png" --appearance light --surface menu
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/menu-dark.png" --appearance dark --surface menu
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/menu-ai-light.png" --appearance light --surface menu-ai
	@"$(BUILD_DIR)/$(EXEC)" --render-ui "$(DIST)/renders/menu-ai-dark.png" --appearance dark --surface menu-ai

clean:
	swift package clean
	@rm -rf "$(DIST)"
