# Changelog

## Unreleased

- Added sortable package tables for installed packages, search results, and outdated packages.
- Improved the package details panel with selected-package actions, clearer metadata, and a more useful empty state.
- Tightened core panel padding to make the main window more compact.
- Reworked the main layout into Search, Manage, and Health tabs, with installed and outdated packages combined in Manage.

## 0.1.1

Release-prep and usability polish.

- Added Homebrew install guidance for the project tap.
- Documented the current unsigned-app Gatekeeper/quarantine workaround.
- Added a build-and-install-from-source route for users who prefer to avoid downloaded unsigned app bundles.
- Added visible current-operation progress in the command output panel while Homebrew commands run.
- Added plain-English command failure summaries for common Homebrew issues while keeping raw command output visible.
- Classifies common failures such as permissions, Xcode Command Line Tools, package not found, already installed/not installed, network/download problems, and macOS security/quarantine blocks.

## 0.1.0

Initial prototype release.

- Native SwiftUI macOS app.
- Homebrew detection and missing-Homebrew install prompt.
- Installed formula/cask listing and filtering.
- Combined Homebrew search with formula/cask classification.
- Install, uninstall, update, and upgrade workflows with confirmation dialogs.
- Formula uninstall dependant checks.
- Structured package details from `brew info --json=v2`.
- Outdated package view with multi-select upgrades.
- Homebrew health checks with guidance and raw output.
- Collapsible command output log.
- macOS Settings, menus, and shortcuts.
- Unsigned `.app`, `.zip`, and drag-to-Applications `.dmg` packaging.
- Search result installed state refreshes immediately after install/uninstall/upgrade without repeating the search.
