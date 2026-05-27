import AppKit
import SwiftUI

@main
struct PublicanApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "autoRefreshInstalledOnLaunch": true,
            "autoRefreshOutdatedOnLaunch": true,
            "includeSelfUpdatingCasksInOutdated": false,
            "commandOutputExpandedByDefault": true
        ])

        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Homebrew") {
                Button("Refresh Installed") {
                    PublicanCommandPoster.post(.publicanRefreshInstalled)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Check Outdated") {
                    PublicanCommandPoster.post(.publicanRefreshOutdated)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Brew Update") {
                    PublicanCommandPoster.post(.publicanBrewUpdate)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()

                Button("Run Health Check") {
                    PublicanCommandPoster.post(.publicanHealthCheck)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandMenu("Package") {
                Button("Search") {
                    PublicanCommandPoster.post(.publicanSearch)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Focus Search Field") {
                    PublicanCommandPoster.post(.publicanFocusSearch)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("Toggle Command Output") {
                    PublicanCommandPoster.post(.publicanToggleCommandOutput)
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }

        Settings {
            PreferencesView()
        }
    }
}
