# Contributing

Thanks for considering a contribution to Publican.

Publican is a native macOS SwiftUI app that shells out to the local Homebrew executable. Changes should keep that safety model clear: commands that mutate the system must show the exact command and ask for confirmation before running.

## Development Setup

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Homebrew installed locally for runtime testing

Run from source:

```bash
swift run Publican
```

Build:

```bash
swift build
```

Build an app bundle:

```bash
./scripts/build-app.sh
```

Package a local release:

```bash
./scripts/package-release.sh
```

## Pull Requests

- Keep changes focused.
- Include a short explanation of behaviour changes.
- Preserve confirmation prompts for mutating Homebrew commands.
- Avoid committing `.build/`, release zips, DMGs, or local Xcode user state.
- If changing package parsing, test against real `brew` output where possible.

## Coding Notes

- Prefer SwiftUI-native controls and AppKit only where macOS integration needs it.
- Keep Homebrew command execution inside `BrewStore`/`BrewCommandRunner`.
- Keep raw Homebrew output available when Publican summarizes or interprets it.
