export EXTENSION_NAME = AEPUserProfile
PROJECT_NAME = $(EXTENSION_NAME)
TARGET_NAME_XCFRAMEWORK = $(EXTENSION_NAME).xcframework
SCHEME_NAME_XCFRAMEWORK = AEPUserProfileXCFramework

CURR_DIR := ${CURDIR}

SIMULATOR_ARCHIVE_PATH = ./build/ios_simulator.xcarchive/Products/Library/Frameworks/
SIMULATOR_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/ios_simulator.xcarchive/dSYMs/
IOS_ARCHIVE_PATH = ./build/ios.xcarchive/Products/Library/Frameworks/
IOS_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/ios.xcarchive/dSYMs/

lint-autocorrect:
	./Pods/SwiftLint/swiftlint --fix

lint:
	./Pods/SwiftLint/swiftlint lint

check-format:
	swiftformat --lint AEPUserProfile/Sources
	
format:
	swiftformat .

generate-lcov:
	xcrun llvm-cov export -format="lcov" .build/debug/AEPRulesEnginePackageTests.xctest/Contents/MacOS/AEPRulesEnginePackageTests -instr-profile .build/debug/codecov/default.profdata > info.lcov

pod-install:
	(pod install --repo-update)

pod-repo-update:
	(pod repo update)

pod-update: pod-repo-update
	(pod update)

open:
	open $(PROJECT_NAME).xcworkspace

clean:
	(rm -rf build)

# Create a simulator from the newest installed iOS runtime + an iPhone device type, instead of
# hardcoding a device name or relying on pre-created simulators. GitHub runners rotate their
# Xcode/simulator lineup (e.g. iPhone 15/16 dropped for 16e/17) and sometimes ship runtimes with no
# pre-created devices, so both fixed names and `-showdestinations` eventually break. Creating the
# device on the fly from whatever runtime is installed is resilient to all of that, and using the
# newest runtime keeps tests on the latest iOS per Apple's guidance. The device is deleted after.
test: clean
	@echo "######################################################################"
	@echo "### Testing iOS"
	@echo "######################################################################"
	@set -e; \
	runtime=$$(xcrun simctl list runtimes iOS 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1); \
	devtype=$$(xcrun simctl list devicetypes 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimDeviceType.iPhone-[0-9A-Za-z-]+' | tail -1); \
	if [ -z "$$runtime" ] || [ -z "$$devtype" ]; then \
		echo "error: no iOS simulator runtime or iPhone device type available"; \
		xcrun simctl list runtimes iOS || true; \
		exit 1; \
	fi; \
	sim_id=$$(xcrun simctl create "ci-$(PROJECT_NAME)-tests" "$$devtype" "$$runtime"); \
	trap "xcrun simctl delete $$sim_id >/dev/null 2>&1 || true" EXIT; \
	echo "### Using iOS Simulator: $$sim_id ($$devtype on $$runtime)"; \
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme $(PROJECT_NAME)Tests -destination "id=$$sim_id" -derivedDataPath build/out -enableCodeCoverage YES

archive: clean pod-install
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios.xcarchive" -sdk iphoneos -destination="iOS" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios_simulator.xcarchive" -sdk iphonesimulator -destination="iOS Simulator" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild -create-xcframework -framework $(SIMULATOR_ARCHIVE_PATH)$(EXTENSION_NAME).framework -debug-symbols $(SIMULATOR_ARCHIVE_DSYM_PATH)$(EXTENSION_NAME).framework.dSYM -framework $(IOS_ARCHIVE_PATH)$(EXTENSION_NAME).framework -debug-symbols $(IOS_ARCHIVE_DSYM_PATH)$(EXTENSION_NAME).framework.dSYM -output ./build/$(TARGET_NAME_XCFRAMEWORK)

zip:
	cd build && zip -r $(EXTENSION_NAME).xcframework.zip $(EXTENSION_NAME).xcframework/
	swift package compute-checksum build/$(EXTENSION_NAME).xcframework.zip

latest-version:
	(which jq)
	(pod spec cat AEPUserProfile | jq '.version' | tr -d '"')

version-podspec-local:
	(which jq)
	(pod ipc spec AEPUserProfile.podspec | jq '.version' | tr -d '"')

podspec-local-dependency-version:
	(which jq)
	(echo "AEPUserProfile:")
	(echo " -AEPService: $(shell pod ipc spec AEPUserProfile.podspec | jq '.dependencies.AEPServices[0]'| tr -d '"')")
	(echo " -AEPCore: $(shell pod ipc spec AEPUserProfile.podspec | jq '.dependencies.AEPCore[0]'| tr -d '"')")

version-source-code:
	(cat ./AEPUserProfile/Sources/UserProfileConstants.swift | egrep '\s*EXTENSION_VERSION\s*=\s*\"(.*)\"' | ruby -e "puts gets.scan(/\"(.*)\"/)[0] " | tr -d '"')

# make check-version VERSION=3.0.1
check-version:
	(sh ./script/version.sh $(VERSION))

test-SPM-integration:
	(sh ./script/test-SPM.sh)

test-podspec:
	(sh ./script/test-podspec.sh)

pod-lint:
	(pod lib lint --allow-warnings --verbose --swift-version=5.1)