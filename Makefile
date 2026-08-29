XCODEBUILD := xcodebuild -scheme syures -destination platform=macOS -derivedDataPath .build -quiet

.PHONY: dev build

# Debug build, restart the running app.
dev:
	$(XCODEBUILD) -configuration Debug build
	-pkill -x syures && sleep 0.5
	open -n .build/Build/Products/Debug/syures.app

# Release build.
build:
	$(XCODEBUILD) -configuration Release build
	@echo "built .build/Build/Products/Release/syures.app"
