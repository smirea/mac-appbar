#!/usr/bin/env bash
set -euo pipefail

app_name="MacAppBar"
bundle_id="dev.stefan.MacAppBar"
release_dir=".build/release"
bundle_path="$release_dir/$app_name.app"
executable_path="$release_dir/$app_name"

swift build -c release

trash "$bundle_path" 2>/dev/null || true
mkdir -p "$bundle_path/Contents/MacOS"

cp "$executable_path" "$bundle_path/Contents/MacOS/$app_name"

/usr/libexec/PlistBuddy -c "Clear dict" "$bundle_path/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $app_name" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bundle_id" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $app_name" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$bundle_path/Contents/Info.plist"

echo "Built $bundle_path"
