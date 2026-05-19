# Publican

Publican is a native macOS SwiftUI front end for [Homebrew](https://brew.sh/). It provides a safer visual workflow for browsing, installing, uninstalling, updating, upgrading, and diagnosing local Homebrew packages.

Publican is currently an early app/prototype. It calls the local `brew` executable directly and shows confirmation dialogs before commands that change the system.

## Features

- Detects whether Homebrew is installed.
- If Homebrew is missing, shows the official install page, copyable install command, and a re-check button.
- Lists installed formulae and casks.
- Filters installed and outdated packages locally.
- Searches Homebrew using the same plain search behaviour as `brew search <term>`, then classifies results into formula and cask sections.
- Installs and uninstalls selected packages.
- Refreshes visible package state after install, uninstall, or upgrade so search results update without repeating the search.
- Checks installed formula dependants before confirming uninstall.
- Shows structured package details from `brew info --json=v2`.
- Opens package homepages and copies package names or exact `brew` commands from package action menus.
- Shows outdated formulae and casks, including installed/current versions when Homebrew provides them.
- Upgrades one or more selected outdated packages, grouping formulae and casks into the correct commands.
- Runs `brew update`.
- Runs `brew doctor` and highlights common health issues such as permissions, Xcode Command Line Tools, outdated packages, and unbrewed files.
- Keeps raw command output visible in a collapsible log.
- Provides macOS Settings for launch refresh and command output defaults.
- Includes native macOS menus and keyboard shortcuts.
- Builds an unsigned `.app`, release `.zip`, and `.dmg`.

## Requirements

- macOS 13 Ventura or newer
- Xcode Command Line Tools
- Homebrew installed locally for package management features

Publican looks for Homebrew at:

- `/opt/homebrew/bin/brew`
- `/usr/local/bin/brew`

## Run From Source

For development:

```bash
cd /Users/openclaw/.openclaw/workspace/Publican
swift run Publican
```

If macOS leaves keyboard focus in Terminal after launch, click the Publican window once.

## Build The App Bundle

```bash
cd /Users/openclaw/.openclaw/workspace/Publican
./scripts/build-app.sh
open .build/Publican.app
```

This creates an unsigned app bundle at:

```text
.build/Publican.app
```

## Package A Release

```bash
cd /Users/openclaw/.openclaw/workspace/Publican
./scripts/package-release.sh
```

This creates:

```text
.build/dist/Publican-macOS.zip
.build/dist/Publican-macOS.dmg
```

The DMG contains `Publican.app` and an `Applications` alias so the app can be dragged into `/Applications`.

Use either file to move Publican to another Mac, such as MacBook Neo.

## Preparing A GitHub Release

Before publishing a release publicly:

1. Run `swift build`.
2. Run `./scripts/package-release.sh`.
3. Test the generated `.dmg` on a clean Mac user account or secondary Mac.
4. Confirm the app still asks before mutating Homebrew commands.
5. Add release notes from `CHANGELOG.md`.
6. Sign and notarise the app if the release is intended for general public use.

## Installing On Another Mac

Because Publican is currently unsigned, macOS Gatekeeper may block it the first time.

Use this flow:

1. Copy `Publican-macOS.zip` or `Publican-macOS.dmg` to the Mac.
2. Extract or mount it.
3. Drag `Publican.app` to Applications if desired.
4. Right-click `Publican.app`.
5. Choose **Open**.
6. Confirm the prompt.

For normal public distribution, Publican should be signed and notarised with an Apple Developer ID certificate.

## Keyboard Shortcuts

- `Cmd+R` - Refresh installed packages
- `Shift+Cmd+R` - Check outdated packages
- `Shift+Cmd+U` - Run `brew update`
- `Shift+Cmd+D` - Run health check
- `Cmd+F` - Focus search field
- `Shift+Cmd+F` - Run search
- `Cmd+L` - Toggle command output

## Safety Model

Publican does not bundle or replace Homebrew. It runs the local `brew` command with `Process`.

Commands that change the system are routed through confirmation dialogs, including:

- install
- uninstall
- update
- upgrade

Uninstalling formulae includes a dependant check using:

```bash
brew uses --installed <package>
```

This is intended to reduce accidental removals of packages used by other installed formulae.

## Signing And Notarisation

This machine currently has no valid macOS code-signing identity installed.

To distribute Publican publicly, use an Apple Developer account and a **Developer ID Application** certificate, then sign the app bundle with hardened runtime, notarise the release archive, and staple the notarisation result.

Typical signing command:

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  .build/Publican.app
```

Typical notarisation command:

```bash
xcrun notarytool submit .build/dist/Publican-macOS.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait
```

Then staple:

```bash
xcrun stapler staple .build/Publican.app
```

The packaging script does not yet automate signing/notarisation.

## Project Structure

```text
Sources/PublicanApp/
  PublicanApp.swift          App entry point, menus, settings scene
  ContentView.swift          Main UI
  BrewStore.swift            App state and Homebrew operations
  BrewCommandRunner.swift    Process wrapper for brew commands
  BrewModels.swift           Data models
  PreferencesView.swift      macOS Settings UI
  PublicanCommands.swift     Menu command notifications
  WindowSizingView.swift     Native window sizing helper

Packaging/
  Info.plist
  Resources/Publican.icns

scripts/
  build-app.sh
  package-release.sh
  generate-icon.swift
```

## Current Limitations

- Publican is unsigned.
- The release package is suitable for personal/testing use, not polished public distribution.
- Homebrew permission problems must still be fixed outside Publican.
- The UI is functional but still needs a compact-layout polish pass.
- There is no automated test suite yet.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

Security-sensitive issues should be handled privately first. See [SECURITY.md](SECURITY.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

Publican is released under the MIT License. See [LICENSE](LICENSE).

## Version

Current app bundle version: `0.1.0`.
