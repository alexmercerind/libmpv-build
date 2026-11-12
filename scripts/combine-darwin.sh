#!/bin/bash
set -euo pipefail
slices="$1"
out="$2"
rm -rf "$out"
mkdir -p "$out/macos-universal" "$out/ios-simulator-universal" "$out/ios-universal"
unzip -q -o "$slices/macos-arm64/libmpv_macos_arm64_audio.zip" -d "$slices/macos-arm64/xc"
unzip -q -o "$slices/macos-amd64/libmpv_macos_amd64_audio.zip" -d "$slices/macos-amd64/xc"
unzip -q -o "$slices/ios-arm64/libmpv_ios_arm64_audio.zip" -d "$slices/ios-arm64/xc"
unzip -q -o "$slices/ios-simulator-arm64/libmpv_ios_simulator-arm64_audio.zip" -d "$slices/ios-simulator-arm64/xc"
unzip -q -o "$slices/ios-simulator-amd64/libmpv_ios_simulator-amd64_audio.zip" -d "$slices/ios-simulator-amd64/xc"
macos_arm64_fw=$(echo "$slices/macos-arm64/xc/Mpv.xcframework"/*/Mpv.framework)
macos_amd64_fw=$(echo "$slices/macos-amd64/xc/Mpv.xcframework"/*/Mpv.framework)
test -f "$macos_arm64_fw/Versions/A/Mpv"
test -f "$macos_amd64_fw/Versions/A/Mpv"
cp -R "$macos_arm64_fw" "$out/macos-universal/Mpv.framework"
lipo -create "$macos_arm64_fw/Versions/A/Mpv" "$macos_amd64_fw/Versions/A/Mpv" -output "$out/macos-universal/Mpv.framework/Versions/A/Mpv"
codesign --force --sign - "$out/macos-universal/Mpv.framework/Versions/A/Mpv"
lipo -info "$out/macos-universal/Mpv.framework/Versions/A/Mpv"
xcodebuild -create-xcframework -framework "$out/macos-universal/Mpv.framework" -output "$out/macos-universal/Mpv.xcframework"
ios_arm64_fw=$(echo "$slices/ios-arm64/xc/Mpv.xcframework"/*/Mpv.framework)
ios_sim_arm64_fw=$(echo "$slices/ios-simulator-arm64/xc/Mpv.xcframework"/*/Mpv.framework)
ios_sim_amd64_fw=$(echo "$slices/ios-simulator-amd64/xc/Mpv.xcframework"/*/Mpv.framework)
test -f "$ios_arm64_fw/Versions/A/Mpv"
test -f "$ios_sim_arm64_fw/Versions/A/Mpv"
test -f "$ios_sim_amd64_fw/Versions/A/Mpv"
cp -R "$ios_sim_arm64_fw" "$out/ios-simulator-universal/Mpv.framework"
lipo -create "$ios_sim_arm64_fw/Versions/A/Mpv" "$ios_sim_amd64_fw/Versions/A/Mpv" -output "$out/ios-simulator-universal/Mpv.framework/Versions/A/Mpv"
codesign --force --sign - "$out/ios-simulator-universal/Mpv.framework/Versions/A/Mpv"
lipo -info "$out/ios-simulator-universal/Mpv.framework/Versions/A/Mpv"
xcodebuild -create-xcframework -framework "$ios_arm64_fw" -framework "$out/ios-simulator-universal/Mpv.framework" -output "$out/ios-universal/Mpv.xcframework"
cd "$out/macos-universal"
zip -qry "$out/libmpv_macos_universal_audio.zip" Mpv.xcframework
cd "$out/ios-universal"
zip -qry "$out/libmpv_ios_universal_audio.zip" Mpv.xcframework
