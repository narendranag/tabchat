# CI calls these recipe names; keep them stable.
project := "Tabchat.xcodeproj"
derived := "build/DerivedData"
# Signing identity; CI sets TABCHAT_SIGN_IDENTITY=- (ad-hoc) because it has no certificate.
sign := env_var_or_default("TABCHAT_SIGN_IDENTITY", "Apple Development")
xb := "xcodebuild -project " + project + " -scheme Tabchat -derivedDataPath " + derived + " CODE_SIGN_IDENTITY='" + sign + "'"

default:
    @just --list

gen:
    xcodegen generate --quiet

build: gen
    {{xb}} -configuration Debug build

test: gen
    {{xb}} -configuration Debug test

lint:
    swiftformat --lint .
    swiftlint --strict

format:
    swiftformat .

run: build
    open "{{derived}}/Build/Products/Debug/Tabchat.app"

release: gen
    {{xb}} -configuration Release build
    @echo "build/DerivedData/Build/Products/Release/Tabchat.app"

dmg: release
    #!/bin/bash
    set -e
    APP="{{derived}}/Build/Products/Release/Tabchat.app"
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
    DMG="build/Tabchat-$VERSION.dmg"
    STAGE=$(mktemp -d)
    trap "rm -rf $STAGE" EXIT

    # Stage the app and Applications symlink
    cp -r "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"

    # Create the DMG
    hdiutil create -volname Tabchat -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    echo "$DMG"
