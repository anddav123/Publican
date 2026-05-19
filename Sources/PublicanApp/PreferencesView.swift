import SwiftUI

struct PreferencesView: View {
    @AppStorage("autoRefreshInstalledOnLaunch") private var autoRefreshInstalledOnLaunch = true
    @AppStorage("autoRefreshOutdatedOnLaunch") private var autoRefreshOutdatedOnLaunch = true
    @AppStorage("commandOutputExpandedByDefault") private var commandOutputExpandedByDefault = true

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Refresh installed packages on launch", isOn: $autoRefreshInstalledOnLaunch)
                Toggle("Refresh outdated packages on launch", isOn: $autoRefreshOutdatedOnLaunch)
            }

            Section("Command Output") {
                Toggle("Expand command output by default", isOn: $commandOutputExpandedByDefault)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
