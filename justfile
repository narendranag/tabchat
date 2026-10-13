# CI calls these recipe names; keep them stable.
project := "Tabchat.xcodeproj"
derived := "build/DerivedData"
xb := "xcodebuild -project " + project + " -scheme Tabchat -derivedDataPath " + derived

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
