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

# Pick a simulator on the newest available iOS runtime via Xcode's own destination enumeration,
# instead of hardcoding a device name. GitHub runners rotate their Xcode/simulator lineup over time
# (e.g. iPhone 15/16 dropped for iPhone 16e/17), so a fixed name eventually breaks; this adapts to
# whatever is installed and, per Apple's guidance, tests against the latest iOS runtime.
test: clean
	@echo "######################################################################"
	@echo "### Testing iOS"
	@echo "######################################################################"
	@set -e; \
	sim_id=$$(xcodebuild -showdestinations -workspace $(PROJECT_NAME).xcworkspace -scheme $(PROJECT_NAME)Tests 2>/dev/null \
		| grep 'platform:iOS Simulator' \
		| sed -nE 's/.*id:([0-9A-Fa-f-]{36}).*OS:([0-9.]+).*/\2 \1/p' \
		| sort -rV | head -1 | cut -d' ' -f2); \
	if [ -z "$$sim_id" ]; then \
		echo "error: no iOS Simulator destination available for $(PROJECT_NAME)Tests"; \
		echo "installed simulator runtimes:"; xcrun simctl list runtimes iOS || true; \
		exit 1; \
	fi; \
	echo "### Using iOS Simulator (newest available runtime): $$sim_id"; \
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