#!/usr/bin/env bash
set -euo pipefail

echo "==> Generating Xcode project with XcodeGen..."
xcodegen generate

echo "==> Cleaning previous build artifacts..."
rm -rf build
mkdir -p build

echo "==> Building Release archive for iOS Device..."
xcodebuild archive \
  -project AoE2-iOS.xcodeproj \
  -scheme AoE2 \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AoE2.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

echo "==> Packaging unsigned IPA..."
mkdir -p build/Payload
cp -R build/AoE2.xcarchive/Products/Applications/AoE2.app build/Payload/
cd build
zip -qr AoE2-unsigned.ipa Payload
cp AoE2-unsigned.ipa AoE2.ipa
cd ..

echo "==> IPA built successfully: build/AoE2-unsigned.ipa"
ls -lh build/AoE2-unsigned.ipa
