---
id: building
title: Building
order: 3
summary: "Requirements, development environment, and build commands."
status: provisional
updated: 2026-10-13
audience: [developers]
depends_on: [index]
related: [architecture]
defines: []
answers:
  - What do I need to build Tabchat?
  - How do I build, test and run it?
  - What is the development workflow?
---

# Building

## Requirements

- **macOS** 14 Sonoma or later (to run the app; the app targets macOS 14+)
- **Apple Silicon** (M1 or later; Intel not supported)
- **Xcode** 26 or later (Swift 6; CI uses 26.6, development uses 27)
- **Homebrew** (for build tools)

## Development environment

Install build tools:

```sh
brew install xcodegen swiftlint swiftformat just
```

These are used by the build recipes:
- **xcodegen:** Generates the Xcode project from `project.yml`
- **swiftlint:** Lints Swift code for style and correctness
- **swiftformat:** Auto-formats Swift code
- **just:** Task runner (like `make`, but simpler; recipes in `justfile`)

## Build commands

All commands use `just` to run recipes defined in `justfile`. The recipes generate the Xcode project (`xcodegen`) and then run Xcode commands.

### Generate Xcode project

```sh
just gen
```

Generates `Tabchat.xcodeproj` from `project.yml`. Run this after any change to `project.yml` or when syncing from remote.

### Build

```sh
just build
```

Builds the app for release. Output: `build/DerivedData/Build/Products/Release/Tabchat.app`.

### Run

```sh
just run
```

Builds and runs the app in the simulator or on the current Mac.

### Test

```sh
just test
```

Runs XCTest unit and integration tests. Tests are in `Tests/`.

### Lint

```sh
just lint
```

Runs swiftlint to check for style and correctness issues. Errors block CI; warnings are logged.

### Format

```sh
just format
```

Auto-formats Swift code with swiftformat. Useful before committing.

### Release

```sh
just release
```

Builds the app in Release configuration. Output: `build/DerivedData/Build/Products/Release/Tabchat.app`.

### Packaging

```sh
just dmg
```

Builds the app and packages it as a `.dmg` installer at `build/Tabchat-<version>.dmg`, where version is read from the app's `CFBundleShortVersionString` in Info.plist.

The DMG contains:
- **Tabchat.app:** The signed application
- **Applications symlink:** For easy installation (drag-and-drop to Applications)

The app is signed with the local `Apple Development` identity (team `4HL2424MH6`). On another Mac without this certificate, Gatekeeper will block the app. To run it:
- Right-click the app and select "Open"
- Or go to System Settings → Privacy & Security → Open Anyway

## Code signing

Local builds sign with the `Apple Development` identity of team `4HL2424MH6` (a free Personal Team
certificate in the login keychain). A stable identity matters: WebKit keeps a "Tabchat WebCrypto
Master Key" in the keychain, and an ad-hoc signature changes on every build, so Keychain would ask
for permission after each rebuild.

Without the certificate (CI, another Mac), sign ad-hoc:

```sh
TABCHAT_SIGN_IDENTITY=- just build
```

CI sets `TABCHAT_SIGN_IDENTITY=-`. Distribution signing (Developer ID, notarisation) is planned.

## Development workflow

1. **Clone and install:**
   ```sh
   git clone https://github.com/narendranag/tabchat.git
   cd tabchat
   brew install xcodegen swiftlint swiftformat just
   ```

2. **Generate and build:**
   ```sh
   just gen
   just build
   ```

3. **Run locally:**
   ```sh
   just run
   ```
   or open `Tabchat.xcodeproj` in Xcode and build from there.

4. **Make changes:**
   - Edit Swift code in `App/Sources/`
   - Add or change tests in `Tests/`
   - If `project.yml` changes, run `just gen` again

5. **Before committing:**
   ```sh
   just format
   just lint
   just test
   ```

6. **CI/CD:**
   - Push to `main` or open a PR
   - GitHub Actions runs `just lint`, `just test`, `just build` automatically (see `.github/workflows/ci.yml`)

## Debugging

### In Xcode

1. Open `Tabchat.xcodeproj`
2. Set breakpoints in Swift code
3. Run with `Cmd+R` or the Play button
4. Use the Debug navigator and console

### App logs

The app logs to the standard system log and to `~/Library/Logs/Tabchat/`. View with:

```sh
log show --predicate 'process == "Tabchat"' --level debug
```

## Planned (not yet built)

- Release build with Developer ID signing and notarization
- Sparkle updates
- Auto-formatting in CI (optional, on PR review)
