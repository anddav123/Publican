# GitHub Release Checklist

Use this before publishing a Publican release.

## Repository

- [ ] Confirm `README.md` is current.
- [ ] Confirm `CHANGELOG.md` has release notes.
- [ ] Confirm `LICENSE`, `CONTRIBUTING.md`, and `SECURITY.md` are present.
- [ ] Confirm `.github/` templates and build workflow are present.
- [ ] Confirm `.build/`, release archives, and local user files are not committed.

## Build

- [ ] Run `swift build`.
- [ ] Run `./scripts/package-release.sh`.
- [ ] Verify `.build/dist/Publican-macOS.zip`.
- [ ] Verify `.build/dist/Publican-macOS.dmg`.
- [ ] Mount the DMG and confirm it contains `Publican.app` and the `Applications` alias.

## Manual Smoke Test

- [ ] Launch Publican.
- [ ] Confirm Homebrew is detected.
- [ ] Search for a cask such as `gimp`.
- [ ] Select a package and confirm package info loads.
- [ ] Confirm install/update/upgrade/uninstall actions show confirmation dialogs before running.
- [ ] Confirm command output can be collapsed and expanded.
- [ ] Confirm Settings opens.

## Public Distribution

- [ ] Sign the app with a Developer ID Application certificate.
- [ ] Notarise the release archive.
- [ ] Staple the notarisation ticket.
- [ ] Re-test Gatekeeper behaviour on another Mac.

Unsigned builds are suitable for local testing, but signed and notarised builds are strongly preferred for public releases.

