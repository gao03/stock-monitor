PROJECT := StockMonitorNative.xcodeproj
SCHEME := StockMonitorNativeApp
CONFIGURATION ?= Debug
DERIVED_DATA ?= .build/xcode-project
DESTINATION ?= platform=macOS
RUST_MANIFEST := rust/longbridge-bridge/Cargo.toml
RUST_PROFILE_DIR = $(if $(filter Release,$(CONFIGURATION)),release,debug)
APP_BUNDLE = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/StockMonitorNative.app
SIDECAR_BINARY = rust/longbridge-bridge/target/$(RUST_PROFILE_DIR)/longbridge-bridge
RELEASE_ARCHIVE := .build/StockMonitorNative-Release.zip

.PHONY: help app-icon build app release package-release run test xcode-test rust-build rust-release rust-test bundle-sidecar fmt fmt-check clean

help:
	@echo "StockMonitorNative build targets:"
	@echo "  make build       Build Rust sidecar and macOS app"
	@echo "  make app-icon    Render AppIcon PNGs from assets/app-icon.png"
	@echo "  make app         Build the macOS app with xcodebuild"
	@echo "  make release     Build the Release app and bundle the Rust sidecar"
	@echo "  make package-release Build and zip the Release app"
	@echo "  make run         Run the SwiftPM executable"
	@echo "  make test        Run SwiftPM tests"
	@echo "  make xcode-test  Run the Xcode test action"
	@echo "  make rust-build  Build the Longbridge Rust sidecar"
	@echo "  make rust-release Build the Longbridge Rust sidecar in release mode"
	@echo "  make rust-test   Run Rust sidecar tests"
	@echo "  make fmt-check   Check Swift and Rust formatting"
	@echo "  make fmt         Format Swift and Rust sources"
	@echo "  make clean       Remove SwiftPM and Xcode build outputs"

build: rust-build app bundle-sidecar

app-icon:
	sh scripts/generate_app_icon.sh

app:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination '$(DESTINATION)' build

release: CONFIGURATION := Release
release: rust-release app bundle-sidecar

package-release: CONFIGURATION := Release
package-release: release
	ditto -c -k --keepParent '$(APP_BUNDLE)' $(RELEASE_ARCHIVE)

run:
	swift run StockMonitorNative

test:
	swift test

xcode-test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) -destination '$(DESTINATION)' test

rust-build:
	cargo build --manifest-path $(RUST_MANIFEST)

rust-release:
	cargo build --release --manifest-path $(RUST_MANIFEST)

rust-test:
	cargo test --manifest-path $(RUST_MANIFEST)

bundle-sidecar:
	cp $(SIDECAR_BINARY) '$(APP_BUNDLE)/Contents/MacOS/longbridge-bridge'
	chmod +x '$(APP_BUNDLE)/Contents/MacOS/longbridge-bridge'
	codesign --force --sign - '$(APP_BUNDLE)/Contents/MacOS/longbridge-bridge'
	codesign --force --deep --sign - '$(APP_BUNDLE)'

fmt:
	swift format format --configuration .swift-format --recursive --in-place Sources Tests
	cargo fmt --manifest-path $(RUST_MANIFEST)

fmt-check:
	swift format lint --configuration .swift-format --recursive Sources Tests
	cargo fmt --manifest-path $(RUST_MANIFEST) --check

clean:
	swift package clean
	rm -rf $(DERIVED_DATA)
